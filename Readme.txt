                           Kubernetes in Azure Cloud

Kubernetes is a portable, extensible, open-source platform for managing containerized
workloads and services, that facilitates both declarative configuration and automation. It has a large,
rapidly growing ecosystem. Kubernetes services, support, and tools are widely available.
In this lab, we will build production design and reproduce the typical steps with
which we will be in touch working with Kubernetes. In the first part of task we need to automate
azure Kubernetes cluster and second part describes build and deployment steps for application
workloads in Kubernetes.

1.At first we should create the following directory layer for deploying our Kubernetes cluster in Azure "Linked Azure Resource Manager template" model.

Lab>
 application:
  app.py,
  Dockerfile,
  requirements.txt
 arm>
  linked:
   acr.json,
   aks.json
  deploy.ps1,
  main.json,  
  parameters.json
 kubernetes:
  Deployment.yaml,
  Service.yaml

Let's start with our Kubernetes cluster and Azure Container Registry deployment in Azure Cloud.
Azure Container Registry allows you to build, store, and manage images for all types of container deployments.
At the top of everything in our lab is an infrastructure,so let's create it with ARM linked templates.
How I showed We have a main.json,parameters.json and deploy.ps1 powershell script to deploy our infrastructure.
In main.json we will define our linked templates (aks.json and acr.json)like this

"resources": [
        {
            "name": "AKS",
            "type": "Microsoft.Resources/deployments",
            "apiVersion": "2019-05-01",
            "dependsOn": [
            ],
            "properties": {
                "mode": "Incremental",
                "templateLink": {
                    "uri": "[variables('AksUri')]",
                    "contentVersion": "1.0.0.0"
                },
                "parameters": {
                    "env": {
                        "value": "[parameters('env')]"
                    },
                    "servicePrincipalClientId": {
                        "value": "[parameters('servicePrincipalClientId')]"
                    },
                    "servicePrincipalClientSecret": {
                        "value": "[parameters('servicePrincipalClientSecret')]"
                    }
                }
            }
        }

And same structure for acs.json(Azure Container Registry).

2.After all deployment Install and configure kubectl that will be used for cluster management.
  https://docs.microsoft.com/en-us/cli/azure/install-azure-cli?view=azure-cli-latest

Login to azure portal:
az login

Install kubectl for Kubernetes cluster management:
az aks install-cli

To configure kubectl to connect to your Kubernetes cluster, use the az aks
get-credentials command. This command downloads credentials and configures the Kubernetes CLI to

use them:
az aks get-credentials --resource-group 'YourResourceGroup' --name 'AKSClusterName'

Test connections:
kubectl get nodes

Create secret for container registry.
This secret file for Pull and Push request from your Kubernetes Cluster to Azure Container Registry.It will listed in your Kubernetes cluster as 'secret'.
Write command 'kubectl get services -n default' and you will see tis secret file
and you should define as a password and username,credentials of Azure Container Registry.
Login to azure portal using azure cli or PowerShell. Download your AKS credential config. Make
sure that you can get access to cluster from your PC. Use the following kubectl command to create the
Kubernetes secret. Replace <acr-login-server> with the fully qualified name of your Azure container
registry (it's in the format "acrname.azurecr.io"). Replace <service-principal-ID> and <service-principalpassword> with the values you obtained by running the previous script. Replace <email-address> with
any well-formed email address.

kubectl create secret docker-registry acr-auth `
--docker-server <acr-login-server> `
--docker-username <service-principal-ID> `
--docker-password <service-principalpassword> `
--docker-email <email-address>

3.Create an empty directory. Change directories (cd) into the new directory, create a file
called Dockerfile, copy-and-paste the following content into that file, and save it. Take note of the
comments that explain each statement in your new Dockerfile.

<< Use an official Python runtime as a parent image
FROM python:2.7-slim
# Set the working directory to /app
WORKDIR /app
# Copy the current directory contents into the container at /app
COPY . /app
# Install any needed packages specified in requirements.txt
RUN pip install --trusted-host pypi.python.org -r requirements.txt
# Make port 80 available to the world outside this container
EXPOSE 80
# Define environment variable
ENV NAME World
# Run app.py when the container launches
CMD ["python", "app.py"]
>>

4.Create 2 files for python application:
Requirements.txt:
Flask
Redis

5.Create an empty directory. Change directories (cd) into the new directory, create a file
called App.py, copy-and-paste the following content into that file, and save it.
<<
from flask import Flask
from redis import Redis, RedisError
import os
import socket
# Connect to Redis
redis = Redis(host="redis", db=0, socket_connect_timeout=2, socket_timeout=2)
app = Flask(__name__)
@app.route("/")
def hello():
 try:
 visits = redis.incr("counter")
 except RedisError:
 visits = "<i>cannot connect to Redis, counter disabled</i>"
 html = "<h3>Hello {name}!</h3>" \
 "<b>Hostname:</b> {hostname}<br/>" \
 "<b>Visits:</b> {visits}"
 return html.format(name=os.getenv("NAME", "world"),
hostname=socket.gethostname(), visits=visits)
if __name__ == "__main__":
 app.run(host='0.0.0.0', port=80)
>>

6.Build application with docker file and push it to Azure Container Registry
Notes: read the article below to get more information about development process that based on
docker:
https://docs.docker.com/get-started/part2/

7.After successful build new image will be stored in Azure Container Registry and you can deploy test application to Kubernetes.
Create two files with content below:
Deployment.yaml

<<
apiVersion: apps/v1
kind: Deployment
metadata:
 name: applicationName
spec:
 selector:
 matchLabels:
 app: applicationName
 replicas: 1
 template:
 metadata:
 labels:
 app: applicationName
 spec:
 containers:
 - name: applicationName
 image: imageName
 ports:
 - containerPort: 80
>>

Service.yaml

<<
apiVersion: v1
kind: Service
metadata:
 name: applicationName
spec:
 selector:
 app: applicationName
 ports:
 - protocol: "TCP"
 port: 80
 targetPort: 80
 type: LoadBalancer
 >>

 Set application name and your docker image that was pushed to Azure Container Registry. Deploy application
using kubectl CLI to Azure aks cluster. As a result of the steps below, you should be able to open the
service by IP.
Kubernetes includes a web dashboard that can be used for basic management
operations. This dashboard lets you view basic health status and metrics for your applications, create
and deploy services, and edit existing applications. To start the Kubernetes dashboard, use the az aks
browse command.
The following example opens the dashboard:
az aks browse --resource-group 'YourResourceGroup' --name 'AKSClusterName'

8.A result of this lab is running application on azure Kubernetes cluster that is available by IP address.