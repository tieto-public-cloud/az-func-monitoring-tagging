using namespace System.Net
# Input bindings are passed in via param block.
param($Timer,$inputTable,$configTable)

Function PostLogData($customerId, $sharedKey, $body, $logType)
{
    $method = "POST"
    $contentType = "application/json"
    $resource = "/api/logs"
    $rfc1123date = [DateTime]::UtcNow.ToString("r")
    $contentLength = $body.Length
    $signature = BuildSignature `
        -customerId $customerId `
        -sharedKey $sharedKey `
        -date $rfc1123date `
        -contentLength $contentLength `
        -method $method `
        -contentType $contentType `
        -resource $resource
    $uri = "https://" + $customerId + ".ods.opinsights.azure.com" + $resource + "?api-version=2016-04-01"
    $headers = @{"Authorization" = $signature; "Log-Type" = $logType; "x-ms-date" = $rfc1123date}
    $response = Invoke-WebRequest -Uri $uri -Method $method -ContentType $contentType -Headers $headers -Body $body
    return $response.StatusCode
}
Function BuildSignature ($customerId, $sharedKey, $date, $contentLength, $method, $contentType, $resource)
{
    $xHeaders = "x-ms-date:" + $date
    $stringToHash = $method + "`n" + $contentLength + "`n" + $contentType + "`n" + $xHeaders + "`n" + $resource
    $bytesToHash = [Text.Encoding]::UTF8.GetBytes($stringToHash)
    $keyBytes = [Convert]::FromBase64String($sharedKey)
    $sha256 = New-Object System.Security.Cryptography.HMACSHA256
    $sha256.Key = $keyBytes
    $calculatedHash = $sha256.ComputeHash($bytesToHash)
    $encodedHash = [Convert]::ToBase64String($calculatedHash)
    $authorization = 'SharedKey {0}:{1}' -f $customerId,$encodedHash
    return $authorization
}
function CleanTable {
    Get-AzTableRow -table $Table | Remove-AzTableRow -table $Table
}
function PushDataToTable {
    param($Resources)
    foreach ($Resource in $Resources) {
        Push-OutputBinding -Name output2Table -Value @{
            PartitionKey = $Timestamp
            Tags = $Resource.Tags
            RowKey = $($Resource.ResourceId).replace('/','|')
        }
    }
}

$TableName          = "ResTags"

Write-Output "Config: $($configTable[0])"
$ResourceGroupName  = $configTable[0].ResourceGroupName
$StorageAccountName = $configTable[0].StorageAccountName
$WorkspaceName      = $configTable[0].WorkspaceName
$Delta              = $configTable[0].Delta # Delta in seconds - if last record in table is older then it will recreate table (to be able to set it once in x hours)

Write-Output "Res Group: $ResourceGroupName"

$WorkspaceKey       = $(Get-AzOperationalInsightsWorkspace -ResourceGroupName $ResourceGroupName -Name $WorkspaceName | Get-AzOperationalInsightsWorkspaceSharedKey).PrimarySharedKey
$StorageAccount     = Get-AzStorageAccount -ResourceGroupName $ResourceGroupName -Name $StorageAccountName
$Context            = $StorageAccount.Context

$Timestamp          = $(Get-Date -UFormat %s)
$Workspace          = Get-AzOperationalInsightsWorkspace -Name $WorkspaceName -ResourceGroupName $ResourceGroupName
$TableData          = $inputTable
$customerId         = $Workspace.CustomerId.Guid 

if ($TableData.length -ne 0){

    $BodyJson = New-Object System.Collections.ArrayList
    foreach ($Row in $TableData){
        $Id = $Row.RowKey.replace('|','/')
        $BodyJson.Add(@{"Id"=$Id;"Tags"=$Row.Tags})
    }
    $BodyJson = $BodyJson | ConvertTo-Json -Compress
    $res = PostLogData -customerId $customerId -sharedKey $WorkspaceKey -body $BodyJson -logType 'TagData'

}

$Table = (Get-AzStorageTable -context $Context -name $TableName).CloudTable

if (($Timestamp - $(Get-AzTableRow -table $Table -Top 1).PartitionKey) -gt $Delta ) {
    $Resources = $(Get-AzResource | Where-Object {$null -ne $_.Tags -and $_.Tags.Count -gt 0} | Select-Object -property ResourceId, Tags )
    CleanTable
    PushDataToTable -Resources $Resources
}

