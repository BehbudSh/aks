Param(
    [string] $ResourceGroupLocation = 'West Europe',
    [string] $ResourceGroupName = 'Module8',
    [string] $StorageAccountName,
    [string] $StorageContainerName = $ResourceGroupName.ToLowerInvariant() + '-stageartifacts',
    [string] $TemplateFile = '.\main.json',
    [string] $TemplateParametersFile = '.\parameters.json',
    [string] $ArtifactStagingDirectory = '.',
    [string] $DockerEmail = 'any well-formed email address'
)

#Azure Service Principal
$ServicePrincipal = New-AzADServicePrincipal -DisplayName ((Get-ChildItem $TemplateFile).BaseName + '-' + ((Get-Date).ToUniversalTime()).ToString('MMdd-HHmm'))

# Create the resource group only when it doesn't already exist
if ($null -eq (Get-AzResourceGroup -Name $ResourceGroupName -Location $ResourceGroupLocation -Verbose -ErrorAction SilentlyContinue)) {
    New-AzResourceGroup -Name $ResourceGroupName -Location $ResourceGroupLocation -Verbose -Force -ErrorAction Stop
}

# Create a storage account name if none was provided
if ($StorageAccountName -eq '') {
    $StorageAccountName = $ResourceGroupName.ToLowerInvariant() + ((Get-AzContext).Subscription.SubscriptionId).Replace('-', '').substring(0, 10)
}
$StorageAccount = (Get-AzStorageAccount | Where-Object { $_.StorageAccountName -eq $StorageAccountName })

# Create the storage account if it doesn't already exist
if ($null -eq $StorageAccount) {
    $StorageAccount = New-AzStorageAccount -StorageAccountName $StorageAccountName -Type 'Standard_LRS' -ResourceGroupName $ResourceGroupName -Location "$ResourceGroupLocation"
}

#Optional Parameters Hash Table for ARM Template
$OptionalParameters = New-Object -TypeName Hashtable

# Convert relative paths to absolute paths
$TemplateFile = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($PSScriptRoot, $TemplateFile))
$TemplateParametersFile = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($PSScriptRoot, $TemplateParametersFile))
$ArtifactStagingDirectory = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($PSScriptRoot, $ArtifactStagingDirectory))
$DSCSourceFolder = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($PSScriptRoot, $DSCSourceFolder))

# _artifactsLocation,_artifactsLocationSasToken,sqlAdministratorLoginPassword,KeyvaultId Parameters Value
$ArtifactsLocationName = '_artifactsLocation'
$ArtifactsLocationSasTokenName = '_artifactsLocationSasToken'
$servicePrincipalClientSecret = 'servicePrincipalClientSecret'
$servicePrincipalClientId = 'servicePrincipalClientId'

# Generate the value for artifacts location if it is not provided in the parameter file
if ($null -eq $OptionalParameters[$ArtifactsLocationName]) {
    $OptionalParameters[$ArtifactsLocationName] = $StorageAccount.Context.BlobEndPoint + $StorageContainerName
}
# Copy files from the local storage staging location to the storage account container
New-AzStorageContainer -Name $StorageContainerName -Context $StorageAccount.Context -ErrorAction SilentlyContinue *>&1
$ArtifactFilePaths = Get-ChildItem $ArtifactStagingDirectory -Recurse -File | ForEach-Object -Process { $_.FullName }
foreach ($SourcePath in $ArtifactFilePaths) {
    Set-AzStorageBlobContent -File $SourcePath -Blob $SourcePath.Substring($ArtifactStagingDirectory.length + 1) `
        -Container $StorageContainerName -Context $StorageAccount.Context -Force
}

# Generate a 4 hour SAS token for the artifacts location if one was not provided in the parameters file
if ($null -eq $OptionalParameters[$ArtifactsLocationSasTokenName]) {
    $OptionalParameters[$ArtifactsLocationSasTokenName] = ConvertTo-SecureString -AsPlainText -Force `
    (New-AzStorageContainerSASToken -Container $StorageContainerName -Context $StorageAccount.Context -Permission r -ExpiryTime (Get-Date).AddHours(4))
}

#Generate the value for Key Value resource parameters
$OptionalParameters[$servicePrincipalClientSecret] = $ServicePrincipal.Secret
$OptionalParameters[$servicePrincipalClientId] = $ServicePrincipal.ApplicationId | ConvertTo-SecureString -AsPlainText -Force

#Arm Template Deployment
$Deployment = New-AzResourceGroupDeployment -Name ((Get-ChildItem $TemplateFile).BaseName + '-' + ((Get-Date).ToUniversalTime()).ToString('MMdd-HHmm')) `
    -ResourceGroupName $ResourceGroupName `
    -TemplateFile $TemplateFile `
    -TemplateParameterFile $TemplateParametersFile `
    @OptionalParameters `
    -Force -Verbose `
    -ErrorVariable ErrorMessages

#kubernetes Variables
$ClusterName = $Deployment.Outputs.clusterName.value
$AcrLoginServer = $Deployment.Outputs.acr.value
$AcrName = $Deployment.Outputs.acrName.value

# Connect to Kubernetes cluster
az aks get-credentials --resource-group $ResourceGroupName --name $Clustername

#Azure Container Registry Credentials
$acrcred = Get-AzContainerRegistryCredential -Name $AcrName -ResourceGroupName $ResourceGroupName
# kubectl command to create the Kubernetes secret for pull/pussh requests from ACR
kubectl create secret docker-registry acr-auth `
    --docker-server $AcrLoginServer `
    --docker-username $acrcred.Username `
    --docker-password $acrcred.Password `
    --docker-email $DockerEmail

#Build application with docker file and push it to docker registry
cd .\application
docker image build -t helloworld .

#Login ACR
az login
az acr login --name $AcrName
#Push the image to Azure Container Registry
docker tag helloworld $AcrLoginServer/helloworld/helloworld:latest
docker push $AcrLoginServer/helloworld/helloworld

#Deploying image to Kubernetes
cd ..\kubernetes
kubectl apply -f Deployment.yaml
kubectl apply -f Service.yaml
cd ..