$organization = "org-name"
$project = "project-name"
$pat = "personal-access-token"
$apiVersion = "7.0"
$header = @{Authorization = 'Basic ' + [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(":$($pat)"))}

$wiqlUri = "https://dev.azure.com/$organization/$project/_apis/wit/wiql?api-version=6.0"

$childTasksQuery = @"
SELECT [System.Id], [System.Title], [System.State], [System.IterationPath], [Custom.ActualEffort]
FROM workitemLinks
WHERE ([Source].[System.TeamProject] = @project AND [Source].[System.WorkItemType] = 'User Story' AND [Source].[System.State] = 'Active')
AND ([System.Links.LinkType] = 'System.LinkTypes.Hierarchy-Forward')
AND ([Target].[System.TeamProject] = @project AND [Target].[System.WorkItemType] = 'Task' AND [Target].[System.State] = 'Complete')
ORDER BY [Microsoft.VSTS.Common.Priority], [System.CreatedDate] DESC
MODE (Recursive)
"@

$childTasksQueryBody = @{
    query = $childTasksQuery
}

$response = Invoke-RestMethod -Uri $wiqlUri -Method Post -ContentType "application/json" -Headers $header -Body (ConvertTo-Json -InputObject $childTasksQueryBody)
$response | ConvertTo-Json

$parentWorkItemUpdates = @{}

foreach ($childTaskRelation in $response.workItemRelations) {
    $childTaskUrl = $childTaskRelation.target.url
    $childTaskState = (Invoke-RestMethod -Uri $childTaskUrl -Method GET -Headers $header).fields.'System.State'

    if ($childTaskState -eq 'Complete') {
        $parentUserStoryUrl = $childTaskRelation.source.url

        # Get the child task's completed work
        $childTask = Invoke-RestMethod -Uri $childTaskUrl -Method GET -Headers $header
        $childActualEffort = $childTask.fields.'Microsoft.VSTS.Scheduling.CompletedWork'

        if ($parentWorkItemUpdates.ContainsKey($parentUserStoryUrl)) {
            # Update existing parent user story's actual effort
            $parentWorkItemUpdates[$parentUserStoryUrl] += $childActualEffort
        }
        else {
            # Add new parent user story with its actual effort
            $parentWorkItemUpdates[$parentUserStoryUrl] = $childActualEffort
        }

        Write-Host "Child task with URL $childTaskUrl has completed work of $childActualEffort hours."
    }
}

foreach ($parentWorkItemUrl in $parentWorkItemUpdates.Keys) {
    $parentActualEffort = $parentWorkItemUpdates[$parentWorkItemUrl]

    $updateUrl = $parentWorkItemUrl -replace "https://dev.azure.com/$organization/$project/", "https://dev.azure.com/$organization/$project/_apis/wit/workitems/"
    $updateUrl += "?api-version=$apiVersion"

    $updateBody = '[{"op": "add", "path": "/fields/Custom.ActualEffort", "value": ' + $parentActualEffort + '}]'
    Invoke-RestMethod -Uri $updateUrl -Method Patch -ContentType "application/json-patch+json" -Headers $header -Body $updateBody

    Write-Host "Parent User Story with URL $parentWorkItemUrl has been updated."
}
