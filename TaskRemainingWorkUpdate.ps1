# Set up variables for Azure DevOps project and credentials
$orgUrl = "organization-name"
$projectName = "project-name"
$pat = "personal access token"

# Authenticate to Azure DevOps
$token = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(":$($pat)"))
$headers = @{Authorization = "Basic $token" }

# Define function to calculate remaining work
function Calculate-RemainingWork ($originalEstimate, $completedWork) {
    $remainingWork = $originalEstimate - $completedWork
    return $remainingWork
}

# Define WIQL query to get all task work items
$query = @"
SELECT [System.Id], [System.WorkItemType], [System.CreatedDate], [System.Title], [Microsoft.VSTS.Scheduling.OriginalEstimate], [Microsoft.VSTS.Scheduling.CompletedWork], [Microsoft.VSTS.Common.ClosedDate]
FROM WorkItems
WHERE [System.WorkItemType] = 'Task'
AND [System.TeamProject] = '$projectName'
AND [System.State] IN ('Backlog', 'Active', 'Blocked', 'Complete')
AND [System.State] <> 'Removed'
AND [Microsoft.VSTS.Common.ClosedDate] = ''
ORDER BY [System.CreatedDate] desc
"@

# Create the WIQL query object
$body = @{query = $query} | ConvertTo-Json

# Post the WIQL query to Azure DevOps
$url = "$orgUrl/$projectName/_apis/wit/wiql?api-version=6.0"
$response = Invoke-RestMethod -Uri $url -Headers $headers -Method Post -ContentType application/json -Body $body
#$workItems = $response.workItems.id

# Get the work items from the query results
$workItems = $response.workItems | Foreach-Object {
    $url = $_.url + "?api-version=6.0"
    Invoke-RestMethod -Uri $url -Headers $headers -Method Get
}



# Loop through all task work items and update Remaining Work field with calculated value
foreach ($workItem in $workItems) {
  #  $url = "$orgUrl/$projectName/_apis/wit/workitems/$($workItem.id)?api-version=6.0"
    $originalEstimate = $workItem.fields.'Microsoft.VSTS.Scheduling.OriginalEstimate'
    $completedWork = $workItem.fields.'Microsoft.VSTS.Scheduling.CompletedWork'
    $remainingWork = Calculate-RemainingWork -originalEstimate $originalEstimate -completedWork $completedWork

    Write-Output "$workItem.id : $remainingWork"

    # Update Remaining Work field for the work item
    $url = "$orgUrl/$projectName/_apis/wit/workitems/$($workItem.id)?api-version=6.0"
    $json = "[{"op": "add","path": "/fields/Microsoft.VSTS.Scheduling.RemainingWork","value": $remainingWork}]"
    $response = Invoke-RestMethod -Uri $url -Headers $headers -Method Patch -ContentType application/json-patch+json -Body $json
}
