$organization = "organization-name"
$project = "project-name"
$pat = "personalaccesstoken"
$customFieldName = "Blocked Hours"
$customblockedDays = "Blocked Days"

# Connect to Azure DevOps using the PAT
$header = $headers = @{Authorization = 'Basic ' + [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(":$($pat)")) }
$uri = "https://dev.azure.com/$organization/$project/_apis/wit/wiql?api-version=6.0"

# Define the WIQL query to get all work items in Blocked state
$query = @"
SELECT [System.Id], [System.Title], [System.WorkItemType], [System.State], [System.CreatedDate], [System.ChangedDate], [Microsoft.VSTS.Common.StateChangeDate]
FROM workitems 
WHERE [System.TeamProject] = '$project' 
AND [System.State] = 'Blocked'
AND [System.State] <> 'Removed'
ORDER BY [System.ChangedDate] DESC
"@

# Execute the WIQL query and get the work item IDs
$response = Invoke-RestMethod -Uri $uri -Method Post -ContentType "application/json" -Headers $header -Body (ConvertTo-Json -InputObject @{query = $query})
$workItemIds = $response.workItems.id

# Loop through the work items and update the value of the custom field
foreach ($workItemId in $workItemIds) {
    $uri = "https://dev.azure.com/$organization/$project/_apis/wit/workitems/$($workItemId)?api-version=6.0"
    $workItem = Invoke-RestMethod -Uri $uri -Method Get -Headers $header

    $blockedHours = 0
    $blockedDays = 0
    $stateChangeDate = $workItem.fields.'Microsoft.VSTS.Common.StateChangeDate'
    if (![string]::IsNullOrWhiteSpace($stateChangeDate)) {
        $blockedDuration = (Get-Date) - [datetime]::Parse($stateChangeDate)
        $blockedHours = [int]$blockedDuration.TotalHours
        $blockedDays = [int]$blockedDuration.TotalDays
    }

    # Output total blocked hours
#Write-Output "Total blocked hours $workItemId : $blockedHours and days : $blockedDays"

    # Set the value of the Blocked hours for the work item
    $jsonCustomFieldValue = "[{"op": "add","path": "/fields/$customFieldName","value": $blockedHours}]"
    Invoke-RestMethod -Uri $uri -Method PATCH -Headers $header -ContentType "application/json-patch+json" -Body $jsonCustomFieldValue

    # Set the value of the Blocked days for the work item
    $jsonCustomFielddaysvalue = "[{"op": "add","path": "/fields/$customblockedDays","value": $blockedDays}]"
    Invoke-RestMethod -Uri $uri -Method PATCH -Headers $header -ContentType "application/json-patch+json" -Body $jsonCustomFielddaysvalue

}
