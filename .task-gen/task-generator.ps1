Param
(
    [Parameter()]
    [string] $pat,

    [Parameter()]
    [string] $organization,

    [Parameter()]
    [string] $project,

    [Parameter()]
    [string] $exercisesFile,

    [Parameter()]
    [string] $attendeesFile
)

$ACCESS_TOKEN = $pat
$COLLECTIONURI = "https://dev.azure.com/$($organization)"
$TEAMPROJECT = $project

Write-Output $ACCESS_TOKEN | az devops login
az devops configure --defaults organization=$COLLECTIONURI project=$TEAMPROJECT

$attendees = (Get-Content $attendeesFile -Raw) | ConvertFrom-Json

$exercises = (Get-Content $exercisesFile -Raw) | ConvertFrom-Json


# Exercise task generator
foreach($feature in $exercises.features){

    Write-Host $feature.title

    $exerciseFeature = az boards query --project $TEAMPROJECT `
        --wiql "SELECT [System.Id], [System.WorkItemType], [System.Title], [System.State], [System.AssignedTo] FROM WorkItems WHERE [Work Item Type] = 'Feature' AND [System.TeamProject] = '$TEAMPROJECT' AND [Title] = '$($feature.title)'" | ConvertFrom-Json

    Write-Host $exerciseFeature

    if($exerciseFeature.Count -gt 0){
    
    } else {

        $exerciseFeature = az boards work-item create `
            --title "$($feature.title)" `
            --description "$($feature.description)" `
            --type 'feature' | ConvertFrom-Json

    }

    foreach($pbi in $feature.pbis){

        Write-Verbose $pbi.title

        foreach($attendee in $attendees.attendees){
            
            Write-Verbose $attendee.name

            $attendeeExerciseWorkItem = az boards query --project $TEAMPROJECT --wiql "SELECT [System.Id], [System.WorkItemType], [System.Title], [System.State], [System.AssignedTo] FROM WorkItems WHERE [Work Item Type] = 'product backlog item' AND [System.TeamProject] = '$TEAMPROJECT' AND [Title] = '$($attendee.name.first) to do $($pbi.title)'" | ConvertFrom-Json

            if($attendeeExerciseWorkItem.Count -gt 0){

                Write-Verbose "Attendee: $($attendee.name) already has work item associated."

            } else {

                Write-Verbose "Doesn't Exists"

                $attendeePBIWorkItem = az boards work-item create `
                    --title "$($pbi.title)" `
                    --description "$($pbi.description)" `
                    --assigned-to $attendee.email `
                    --fields "Microsoft.VSTS.Common.AcceptanceCriteria=$($pbi.'acceptance criteria')" `
                    --type 'product backlog item' | ConvertFrom-Json

                az boards work-item relation add `
                    --id $attendeePBIWorkItem.id `
                    --relation-type parent `
                    --target-id $exerciseFeature[0].id

                foreach($task in $pbi.tasks){

                    Write-Verbose $task.title

                    # Work Item Tasks
                    $attendeeTaskWorkItem = az boards work-item create `
                        --title "$($task.title)" `
                        --description "$($task.description)" `
                        --assigned-to $attendee.email `
                        --type 'task' | ConvertFrom-Json

                    az boards work-item relation add `
                        --id $attendeeTaskWorkItem.id `
                        --relation-type parent `
                        --target-id $attendeePBIWorkItem[0].id
                }
            }
        }
    }
}