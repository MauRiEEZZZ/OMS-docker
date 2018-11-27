# How to add Log Analytics Workspace ResourceId tags to Acs-engine Kubernetes cluster resources

You can either use the Azure Powershell or Azure cli to attach the Azure Resource Id of the Log Analytics workspace and optionally clusterName tag to Acs-engine Kubernetes master nodes. If the clusterName tag attached and that will be used to identify that as cluster name in the UI else its name of the resource group where the acs-engine resources exist. ClusterName should be match with what's configured on the omsagent for omsagent.env.clusterName as part of the omsagent installation. Log Analytics workspace ResourceId tag on the K8s master node used to determine whether the specified cluster is onboarded to monitoring or not.  


These  tags required for the Azure Monitor for Containers Ux experience (https://docs.microsoft.com/en-us/azure/monitoring/monitoring-container-insights-overview )

If you are not familiar with the concepts of azure resource tags (https://docs.microsoft.com/en-us/azure/azure-resource-manager/resource-group-using-tags)


## Attach tags using Powershell

Get the below powershell script files to your local computer.
   - Powershell script file [AddMonitoringWorkspaceTags.ps1](https://github.com/Microsoft/OMS-docker/blob/ci_feature/docs/acsengine/kubernetes/AddMonitoringWorkspaceTags.ps1)
   - Refer for updating the Powershell execution policy (https://docs.microsoft.com/en-us/powershell/module/microsoft.powershell.security/set-executionpolicy?view=powershell-6)
   - Log analytics workspace resource Id can retrieved either Azure CLI or Powershell or Azure Portal  
      Azure CLI

      az resource list --resource-type Microsoft.OperationalInsights/workspaces 
                  OR 
      az resource show -g `<resource group of the workspace>` -n `<name of the workspace>` --resource-type Microsoft.OperationalInsights/workspaces

      Powershell

      https://docs.microsoft.com/en-us/powershell/module/azurerm.operationalinsights/get-azurermoperationalinsightsworkspace?view=azurermps-6.11.0

     Azure Portal

     From the Portal URL when the Log Analytics Workspace selected,see below for the format of the Log Analytics Workspace Resource Id

     /subscriptions/`<subId>`/resourceGroups/`<rgName>`/providers/Microsoft.OperationalInsights/workspaces/`<workspaceName>`
       

- Use the following PowerShell command from the folder containing the Powershell script file:

``` sh 

.\AddMonitoringWorkspaceTags.ps1 -SubscriptionId <Acs-Engine SubscriptionId> -ResourceGroupName <Acs-Engine ResourceGroup> -LogAnalyticsWorkspaceResourceId <WorkspaceResourceId>

```

The configuration change can take a few minutes to complete. When it finishes, you see a message something like this 'Successfully added logAnalyticsWorkspaceResourceId tag to K8s master VMs':

## Attach tags using Azure CLI 

- Run the below az cli commands to attach the log analytics workspace resourceId tags to acs-engine K8s master nodes

``` sh 

# login
az login

# Azure resource Id of the workspace configured on the omsagent
workspaceResourceId="/subscriptions/<subscription id>/resourceGroups/<resource group name>/providers/Microsoft.OperationalInsights/workspaces/<workspace name>"

# Azure Monitor for container Ux uses  name of resource group where the acs-engine resources present
# if you have configured name of the cluster for omsagent.env.clusterName parameter on omsagent is different from resource id of resource group
# then you need attach same clusterName as clusterName tag hence replace '' with actual clusterName for below clusterName variable
clusterName=''


# set subscription of the acs-engine resource group
az account set -s <subscriptionId of acs-engine Kubernetes cluster>

# check whether log analytics workspace resource exists or not
az resource show --ids $workspaceResourceId

# get the all existing k8s master nodes
resources=$(az resource list -g <resource group name of acs engine cluster> --resource-type "Microsoft.Compute/virtualMachines" --query "[?starts_with(name,'k8s-master')].id" --output tsv)

# attach logAnalyticsWorkspaceResourceId=<resourceId of the log analytics workspace> to all K8s master nodes 
for resid in $resources
 do
    jsonrtag=$(az resource show --id $resid --query tags)
    rt=$(echo $jsonrtag | tr -d '"{},' | sed 's/: /=/g')
    if [ -z $clusterName ]; then
      az resource tag --tags $rt logAnalyticsWorkspaceResourceId=$workspaceResourceId --id $resid
    else 
       az resource tag --tags $rt logAnalyticsWorkspaceResourceId=$workspaceResourceId clusterName=$clusterName --id $resid        
    fi   
done

```