$organization = "organization-name"
$project = "project-name"
$pat = "personal access token"

$header = @{
    Authorization = 'Basic ' + [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(":$pat"))
}

$wiqlUri = "https://dev.azure.com/$organization/$project/_apis/wit/wiql?api-version=6.0"

$parentQuery = @"
SELECT [System.Id], [System.Title], [System.WorkItemType], [System.State], [System.ChangedDate]
FROM workitems 
WHERE [System.TeamProject] = '$project'
AND [System.WorkItemType] = 'User Story' 
AND [System.State] = 'Backlog'
AND [System.State] <> 'Removed'
ORDER BY [System.ChangedDate] DESC
"@

$childTasksQuery = @"
SELECT [System.Id], [System.Title], [System.State], [System.IterationPath]
FROM workitemLinks
WHERE ([Source].[System.TeamProject] = @project AND [Source].[System.WorkItemType] = 'User Story' AND [Source].[System.State] = 'Backlog')
AND ([System.Links.LinkType] = 'System.LinkTypes.Hierarchy-Forward')
AND ([Target].[System.TeamProject] = @project AND [Target].[System.WorkItemType] = 'Task' AND [Target].[System.State] = 'Active')
ORDER BY [Microsoft.VSTS.Common.Priority], [System.CreatedDate] DESC
MODE (Recursive)
"@

$parentQueryBody = @{
    query = $parentQuery
}

$response = Invoke-RestMethod -Uri $wiqlUri -Method Post -ContentType "application/json" -Headers $header -Body (ConvertTo-Json -InputObject $parentQueryBody)

foreach ($parentWorkItem in $response.workItems) {
    $childTasksQueryBody = @{
        query = $childTasksQuery
    }

    $childTasksResponse = Invoke-RestMethod -Uri $wiqlUri -Method POST -ContentType "application/json" -Headers $header -Body (ConvertTo-Json -InputObject $childTasksQueryBody)

    $hasActiveChildTask = $childTasksResponse.workItemRelations | Where-Object {
        $childTaskId = $_.target.id
        $childTaskUrl = $_.target.url
        $childTaskState = (Invoke-RestMethod -Uri $childTaskUrl -Method GET -Headers $header).fields.'System.State'
        $childTaskState -eq 'Active'
    }

    foreach ($activeChildTask in $hasActiveChildTask) {
        $parentUserStoryUrl = $activeChildTask.source.url
        # Retrieve the source URL
        $sourceUrl = $activeChildTask.source.url

        $parentWorkItemUrl = $parentUserStoryUrl + "?api-version=7.0"
        $parentWorkItemUrl | ConvertTo-Json
        
        $updateBody = "[{"op": "add","path": "/fields/System.State","value": "Active"}]"

        Invoke-RestMethod -Uri $parentWorkItemUrl -Method Patch -ContentType "application/json-patch+json" -Headers $header -Body $updateBody

        Write-Output "Parent User Story with URL $parentUserStoryUrl has been updated to Active."
        Write-Output "Source URL: $sourceUrl"
        }
}
