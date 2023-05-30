$organization = "org-name"
$project = "project-name"
$pat = "personal-access-token"
$desired-state = "Active"

#Authentication
$header = $headers = @{Authorization = 'Basic ' + [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(":$($pat)")) }

$wiqlUri = "https://dev.azure.com/$organization/$project/_apis/wit/wiql?api-version=6.0"

$childTasksQuery = @"
SELECT [System.Id], [System.Title], [System.State], [System.IterationPath]
FROM workitemLinks
WHERE ([Source].[System.TeamProject] = @project AND [Source].[System.WorkItemType] = 'User Story' AND [Source].[System.State] = 'Backlog')
AND ([System.Links.LinkType] = 'System.LinkTypes.Hierarchy-Forward')
AND ([Target].[System.TeamProject] = @project AND [Target].[System.WorkItemType] = 'Task' AND [Target].[System.State] = 'Active')
ORDER BY [Microsoft.VSTS.Common.Priority], [System.CreatedDate] DESC
MODE (Recursive)
"@

$childTasksQueryBody = @{
    query = $childTasksQuery
}

$response = Invoke-RestMethod -Uri $wiqlUri -Method Post -ContentType "application/json" -Headers $header -Body (ConvertTo-Json -InputObject $childTasksQueryBody)

foreach ($childTaskRelation in $response.workItemRelations) {
    $childTaskUrl = $childTaskRelation.target.url
    $childTaskState = (Invoke-RestMethod -Uri $childTaskUrl -Method GET -Headers $header).fields.'System.State'

    if ($childTaskState -eq 'Active') {
        $parentUserStoryUrl = $childTaskRelation.source.url
        $sourceUrl = $childTaskRelation.source.url
        $parentWorkItemUrl = $parentUserStoryUrl + "?api-version=7.0"
        $updateBody = '[{"op": "add", "path": "/fields/System.State", "value": "$desired-state"}]'

        Invoke-RestMethod -Uri $parentWorkItemUrl -Method Patch -ContentType "application/json-patch+json" -Headers $header -Body $updateBody

        Write-Output "Parent User Story with URL $parentUserStoryUrl has been updated to $desired-state."
        Write-Output "Source URL: $sourceUrl"
    }
}
