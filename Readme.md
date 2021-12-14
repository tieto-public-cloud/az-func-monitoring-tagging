# Resource Tags to Log Analytics Workspace - Azure Function

## General Info

We needed to use resource tags with Azure Monitor query based alerts to make easier use of:  
* Monitoring baselines
* Routing tickets to specific team in our CMDB
* Filter resources that we are interested in monitoring (as a service provider)

This is code for Powershell based Azure function that reads subscription resources tags data and stores it to specified log analytics workspace custom log data.  
The function reads configuration from Azure storage account table service (table name Config), also uses this storage account as a temporary storage.

## Function workflow

Due to cost optimization I had decided to make function operate in 2 stages.
The function is executed as a scheduled trigger each minute.

### Stage 1

* This stage is initiated if difference between now and time of creation of the temporary record is greater than Delta configuration property value (or there are not any temporary data stored yet)
* Removes temporary data from ResTags table in specified storage account
* Read resource tags data from subscription where function resides. This should happen once in hour (actually configurable via Delta configruation property) as this operation is quite compute heavy and takes most of the time
* Store data in temporary storage

### Stage 2
* Reads ResTags table content and push it to log analytics workspace

## Configuration properties

* ResourceGroupName - Resource group name with Log Analytics Workspace
* WorkspaceName - Name of the Log Analytics Workspace
* StorageAccountResourceGroup - Resource group with storage account to store temporary resource tag data and containing function Config table
* StorageAccountName - Name of the above storage account
* Delta - amount of seconds that configures how old can temporary data be, before reading new data set

## Permissions

Function needs following permissions:

* Read permissions on whole subscription - so it can read the resource tag data
* Contributor to resource group with function, storage account and log analytics workspace (these may be multiple resource groups actually)
