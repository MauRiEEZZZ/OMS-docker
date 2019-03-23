﻿<# 
    .DESCRIPTION 
       
      Onboards the Kubernetes cluster hosted outside Azure to the Azure Monitor for containers.

      1. Creates the Managed Resource Group with required metadata in Azure Public Cloud to reprents the Kubernetes cluster hosted outside the Azure Public Cloud.
       Managed Resource Group created in same subscription as Azure Log Analytics Workspace and location of the RG is same as workspace.

       Formate of the Managed Resource Group :  MG_<clusterName>_<workspaceLocation>_AzureMonitor

       Following tags are attached to Managed Resource Group   
                      
        ---------------------------------------------------------------------------------------------------------------------------------------------
       | tagName                             | tagValue                                                                                              | 
        ---------------------------------------------------------------------------------------------------------------------------------------------
       |clusterName                          | <name of the kubernetes clusterName. This should be same as configured on the omsagent>               |
       ----------------------------------------------------------------------------------------------------------------------------------------------
       |loganalyticsWorkspaceResourceId      | <azure resource Id of the log analytics workspace. This should be same as configued on the oms agent> |
       ----------------------------------------------------------------------------------------------------------------------------------------------       
       |hosteEnvironment                     | AzureStack or AWS or AME or etc                                                                       |      
       ----------------------------------------------------------------------------------------------------------------------------------------------
       |clusterType                          | AKS-Engine or ACS-Engine or Kubernetes or AKS or GKE or EKS. Default is AKS-Engine.                                                         |
       ----------------------------------------------------------------------------------------------------------------------------------------------
       |creationsource                       | azuremonitorforcontainers.                                                                             |
       ----------------------------------------------------------------------------------------------------------------------------------------------   
       |orchestrator                         | kubernetes. This is only supported orchestrator.                                                                                            |       
       ----------------------------------------------------------------------------------------------------------------------------------------------
     2. Adds the ContainerInsights solution to the specified Log Analytics workspace if the solution doesn't exist     
     
     3. Optinally, locks Managed Resource Group to prevent accidental deletion.
     
     4. TODO - onboard the OMSAgent to the K8s cluster

	See below reference to get the Log Analytics workspace resource Id 
	https://docs.microsoft.com/en-us/powershell/module/azurerm.operationalinsights/get-azurermoperationalinsightsworkspace?view=azurermps-6.11.0
 
    .PARAMETER custerName
        Name of the cluster configured on the OMSAgent
    .PARAMETER loganalyticsWorkspaceResourceId
        Azure ResourceId of the log analytics workspace Id
   .PARAMETER hostedEnvironment
        Named of the Hosted Environment.
   .PARAMETER clusterType
        Type of cluster to onboard. Supported cluster types are AKS-Engine or ACS-Engine or Kubernetes or GKE or EKS.    
#>
param(
    [Parameter(mandatory = $true)]
    [string]$clusterName,
    [Parameter(mandatory = $true)]
    [string]$LogAnalyticsWorkspaceResourceId,
    [Parameter(mandatory = $true)]
    [string]$hosteEnvironment,    
    [string]$clusterType = "AKS-Engine",
    [boolean]$onboardOMSAgent = $false
)

# checks the required Powershell modules exist and if not exists, request the user permission to install
$azAccountModule = Get-Module -ListAvailable -Name Az.Accounts
$azResourcesModule = Get-Module -ListAvailable -Name Az.Resources
$azureRmOperationalInsights = Get-Module -ListAvailable -Name AzureRM.OperationalInsights

if (($null -eq $azAccountModule) -or ($null -eq $azResourcesModule) -or ($null -eq $azureRmOperationalInsights)) {
    
    $currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())

    if ($currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Host("Running script as an admin...")
        Write-Host("")
    }
    else {
        Write-Host("Please re-launch the script with elevated administrator") -ForegroundColor Red
        Stop-Transcript
        exit
    }

    $message = "This script will try to install the latest versions of the following Modules : `
			    Az.Resources and Az.Accounts  using the command`
			    `'Install-Module {Insert Module Name} -Repository PSGallery -Force -AllowClobber -ErrorAction Stop -WarningAction Stop'
			    `If you do not have the latest version of these Modules, this troubleshooting script may not run."
    $question = "Do you want to Install the modules and run the script or just run the script?"

    $choices = New-Object Collections.ObjectModel.Collection[Management.Automation.Host.ChoiceDescription]
    $choices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&Yes, Install and run'))
    $choices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&Continue without installing the Module'))
    $choices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&Quit'))

    $decision = $Host.UI.PromptForChoice($message, $question, $choices, 0)

    switch ($decision) {
        0 { 

            if ($null -eq $azResourcesModule) {
                try {
                    Write-Host("Installing Az.Resources...")
                    Install-Module Az.Resources -Repository PSGallery -Force -AllowClobber -ErrorAction Stop
                }
                catch {
                    Write-Host("Close other powershell logins and try installing the latest modules forAz.Accounts in a new powershell window: eg. 'Install-Module Az.Accounts -Repository PSGallery -Force'") -ForegroundColor Red
                    exit
                }
            }

            if ($null -eq $azAccountModule) {
                try {
                    Write-Host("Installing Az.Accounts...")
                    Install-Module Az.Accounts -Repository PSGallery -Force -AllowClobber -ErrorAction Stop
                }
                catch {
                    Write-Host("Close other powershell logins and try installing the latest modules forAz.Accounts in a new powershell window: eg. 'Install-Module Az.Accounts -Repository PSGallery -Force'") -ForegroundColor Red
                    exit
                }
            }

            if ($null -eq $azureRmOperationalInsights) {
                try {
             
                    Write-Host("Installing AzureRM.OperationalInsights...")
                    Install-Module AzureRM.OperationalInsights -Repository PSGallery -Force -AllowClobber -ErrorAction Stop                
                }
                catch {
                    Write-Host("Close other powershell logins and try installing the latest modules for AzureRM.OperationalInsights in a new powershell window: eg. 'Install-Module AzureRM.OperationalInsights -Repository PSGallery -Force'") -ForegroundColor Red 
                    exit
                }        
            } 
           
        }
        1 {

            if ($null -eq $azResourcesModule) {
                try {
                    Import-Module Az.Resources -ErrorAction Stop
                }
                catch {
                    Write-Host("Could not import Az.Resources...") -ForegroundColor Red
                    Write-Host("Close other powershell logins and try installing the latest modules for Az.Resources in a new powershell window: eg. 'Install-Module Az.Resources -Repository PSGallery -Force'") -ForegroundColor Red
                    Stop-Transcript
                    exit
                }
            }
            if ($null -eq $azAccountModule) {
                try {
                    Import-Module Az.Accounts -ErrorAction Stop
                }
                catch {
                    Write-Host("Could not import Az.Accounts...") -ForegroundColor Red
                    Write-Host("Close other powershell logins and try installing the latest modules for Az.Accounts in a new powershell window: eg. 'Install-Module Az.Accounts -Repository PSGallery -Force'") -ForegroundColor Red
                    Stop-Transcript
                    exit
                }
            } 
            
            try {
                Import-Module AzureRM.OperationalInsights
            }
            catch {
                Write-Host("Could not import AzureRM.OperationalInsights... Please reinstall this Module") -ForegroundColor Red
                Stop-Transcript
                exit
            }         
	
        }
        2 { 
            Write-Host("")
            Stop-Transcript
            exit
        }
    }
}

if ([string]::IsNullOrEmpty($LogAnalyticsWorkspaceResourceId)) {   
    Write-Host("LogAnalyticsWorkspaceResourceId shouldnot be NULL or empty") -ForegroundColor Red
    exit
}

if (($LogAnalyticsWorkspaceResourceId -match "/providers/Microsoft.OperationalInsights/workspaces") -eq $false) {
    Write-Host("LogAnalyticsWorkspaceResourceId should be valid Azure Resource Id format") -ForegroundColor Red
    exit
}

$workspaceResourceDetails = $LogAnalyticsWorkspaceResourceId.Split("/")

if ($workspaceResourceDetails.Length -ne 9) { 
    Write-Host("LogAnalyticsWorkspaceResourceId should be valid Azure Resource Id format") -ForegroundColor Red
    exit
}

$workspaceSubscriptionId = $workspaceResourceDetails[2]
$workspaceSubscriptionId = $workspaceSubscriptionId.Trim()

$workspaceResourceGroupName = $workspaceResourceDetails[4]
$workspaceResourceGroupName = $workspaceResourceGroupName.Trim()

$workspaceName = $workspaceResourceDetails[8]
$workspaceResourceGroupName = $workspaceResourceGroupName.Trim()

Write-Host("LogAnalytics Workspace SubscriptionId : '" + $workspaceSubscriptionId + "' ") -ForegroundColor Green

try {
    Write-Host("")
    Write-Host("Trying to get the current Az login context...")
    $account = Get-AzContext -ErrorAction Stop
    Write-Host("Successfully fetched current AzContext context...") -ForegroundColor Green
    Write-Host("")
}
catch {
    Write-Host("")
    Write-Host("Could not fetch AzContext..." ) -ForegroundColor Yellow
    Write-Host("")
}

if ($null -eq $account.Account) {
    try {
        Write-Host("Please login...")
        Connect-AzAccount -subscriptionid $workspaceSubscriptionId
    }
    catch {
        Write-Host("")
        Write-Host("Could not select subscription with ID : " + $workspaceSubscriptionId + ". Please make sure the ID you entered is correct and you have access to the cluster" ) -ForegroundColor Red
        Write-Host("")
        Stop-Transcript
        exit
    }
}

if ($null -eq $account.Account) {
    try {
        Write-Host("Please login...")
        Login-AzureRmAccount -subscriptionid $workspaceSubscriptionId
    }
    catch {
        Write-Host("")
        Write-Host("Could not select subscription with ID : " + $SubscriptionId + ". Please make sure the ID you entered is correct and you have access to the cluster" ) -ForegroundColor Red
        Write-Host("")
        Stop-Transcript
        exit
    }
}
else {
    if ($account.Subscription.Id -eq $workspaceSubscriptionId) {
        Write-Host("Subscription: $workspaceSubscriptionId is already selected. Account details: ")
        $account
    }
    else {
        try {
            Write-Host("Current Subscription:")
            $account
            Write-Host("Changing to subscription: $workspaceSubscriptionId")
            Select-AzureRmSubscription -SubscriptionId $workspaceSubscriptionId
        }
        catch {
            Write-Host("")
            Write-Host("Could not select subscription with ID : " + $workspaceSubscriptionId + ". Please make sure the ID you entered is correct and you have access to the cluster" ) -ForegroundColor Red
            Write-Host("")
            Stop-Transcript
            exit
        }
    }
}

# validate specified logAnalytics workspace exists and got access permissions
Write-Host("Checking specified LogAnalyticsWorkspaceResourceId exists and got access...")

try {
    Write-Host("Checking workspace name's details...")
    $WorkspaceInformation = Get-AzureRmOperationalInsightsWorkspace -ResourceGroupName $workspaceResourceGroupName -Name $workspaceName -ErrorAction Stop
    Write-Host("Successfully fetched workspace name...") -ForegroundColor Green
    Write-Host("")
}
catch {
    Write-Host("")
    Write-Host("Could not fetch details for the workspace : '" + $workspaceName + "'. Please make sure that it hasn't been deleted and you have access to it.") -ForegroundColor Red        
    Stop-Transcript
    exit
}
	
$WorkspaceLocation = $WorkspaceInformation.Location
		
if ($null -eq $WorkspaceLocation) {
    Write-Host("")
    Write-Host("Cannot fetch workspace location. Please try again...") -ForegroundColor Red
    Write-Host("")
    Stop-Transcript
    exit
}

try {
    $WorkspaceIPDetails = Get-AzureRmOperationalInsightsIntelligencePacks -ResourceGroupName $workspaceResourceGroupName -WorkspaceName $workspaceName -ErrorAction Stop
    Write-Host("Successfully fetched workspace IP details...") -ForegroundColor Green
    Write-Host("")
}
catch {
    Write-Host("")
    Write-Host("Failed to get the list of solutions onboarded to the workspace. Please make sure that it hasn't been deleted and you have access to it.") -ForegroundColor Red
    Write-Host("")
    Stop-Transcript
    exit
}

try {
    $ContainerInsightsIndex = $WorkspaceIPDetails.Name.IndexOf("ContainerInsights");
    Write-Host("Successfully located ContainerInsights solution") -ForegroundColor Green
    Write-Host("")
}
catch {
    Write-Host("Failed to get ContainerInsights solution details from the workspace") -ForegroundColor Red
    Write-Host("")
    Stop-Transcript
    exit
}

$isSolutionOnboarded = $WorkspaceIPDetails.Enabled[$ContainerInsightsIndex]
	
if ($false -eq $isSolutionOnboarded) {
    #
    # Check contributor access to WS
    #
    $message = "Detected that there is a workspace associated with this cluster, but workspace - '" + $workspaceName + "' in subscription '" + $workspaceSubscriptionId + "' IS NOT ONBOARDED with container insights solution.";
    Write-Host($message)
    $question = " Do you want to onboard container health to the workspace?"

    $choices = New-Object Collections.ObjectModel.Collection[Management.Automation.Host.ChoiceDescription]
    $choices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&Yes'))
    $choices.Add((New-Object Management.Automation.Host.ChoiceDescription -ArgumentList '&No'))

    $decision = $Host.UI.PromptForChoice($message, $question, $choices, 0)

    if ($decision -eq 0) {
        Write-Host("Deploying template to onboard container health : Please wait...")            
                        
        $DeploymentName = "ContainerInsightsSolutionOnboarding-" + ((Get-Date).ToUniversalTime()).ToString('MMdd-HHmm')
        $Parameters = @{}
        $Parameters.Add("workspaceResourceId", $LogAnalyticsWorkspaceResourceID)
        $Parameters.Add("workspaceRegion", $WorkspaceLocation)
        $Parameters

        try {
            New-AzureRmResourceGroupDeployment -Name $DeploymentName `
                -ResourceGroupName $workspaceResourceGroupName `
                -TemplateFile https://raw.githubusercontent.com/Microsoft/OMS-docker/ci_feature/docs/templates/azuremonitor-containerSolution.json `
                -TemplateParameterObject $Parameters -ErrorAction Stop`
            Write-Host("")
            Write-Host("Template deployment was successful. You will be able to see data flowing into your cluster in 10-15 mins.") -ForegroundColor Green
            Write-Host("")
        }
        catch {
            Write-Host ("Template deployment failed with an error: '" + $Error[0] + "' ") -ForegroundColor Red
            Write-Host("Please contact us by emailing askcoin@microsoft.com for help") -ForegroundColor Red
        }
    }
    else {
        Write-Host("The container health solution isn't onboarded to your cluster. This required for the monitoring to work. Please contact us by emailing askcoin@microsoft.com if you need any help on this") -ForegroundColor Red
    }
}

Write-Host("Successfully verified specified LogAnalyticsWorkspaceResourceId exist...")

#
#   Check if there is already Managed Resource group exists with this name
#

$managedResourceGroup = "MG_" + $clusterName + "_" + $WorkspaceLocation + "_" + "AzureMonitor"
Write-Host("Creating managed resource group : '" + $managedResourceGroup + "'")

Get-AzureRmResourceGroup -Name $managedResourceGroup -ErrorVariable notPresent -ErrorAction SilentlyContinue

if ($notPresent) {

    Write-Host("creating resource group: '" + $managedResourceGroup + "' + in location : '" + $workspaceResource.Location + "' + ")
    New-AzureRmResourceGroup -Name $clusterName -Location $workspaceResourceLocation
}
else { 
    Write-Host("Manged Resource Group exists already with this name") -ForegroundColor Red
    Write-Host("")
    Stop-Transcript
    exit
}

Write-Host("Successfully created managed resource groups ...") -ForegroundColor Green

# attach tags to the managed resource group
Write-Host("Attaching required tags to managed resource group: '" + $managedResourceGroup + "' ...")
$rg = Get-AzureRmResourceGroup -ResourceGroupName $managedResourceGroup 

$monitoringTags = @{ }

$monitoringTags.Add("clusterName", $clusterName)
$monitoringTags.Add("logAnalyticsWorkspaceResourceId", $LogAnalyticsWorkspaceResourceId)
$monitoringTags.Add("hosteEnvironment", $hosteEnvironment)
$monitoringTags.Add("clusterType", $clusterType)

$monitoringTags.Add("creationsource", "azuremonitorforcontainers")
$monitoringTags.Add("orchestrator", "kubernetes")
 
Set-AzureRmResource -Tag $monitoringTags -ResourceId $rg.ResourceId -Force

Write-Host("Successfully attached required tags to managed resource group: '" + $managedResourceGroup + "' ...")

# locking the managed resource group to prevent accidental deletion or modifcation
# locking the managed resource group
Write-Host("Adding CanNotDelete lock to managed resource group: '" + $managedResourceGroup + "' to avoid accidental deletion...")
New-AzureResourceLock -LockLevel CanNotDelete -LockName azuremonitorforcontainers -ResourceGroupName $managedResourceGroup -ErrorVariable lockError

if ($lockError) {
    Write-Host("Failed add the CanNotDelete lock to resource group: '" + $managedResourceGroup + "' ...")  -ForegroundColor Yellow
}
else {
    Write-Host("Successfully locked resource group: '" + $managedResourceGroup + "' to avoid accidental deletion...") 
}

Write-Host("Successfully onboarded cluster: '" + $clusterName + "' to  azure monitor for containers...") 

Write-Host(" At this point of time, onboarding takes around 24 to 36 hours to apper the cluster in https://aka.ms/azmon-containers-hybrid") 







