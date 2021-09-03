# This isn't complete and more work needs to be done on the PBI; adding description, acceptance criteria as well as all the information around Tasks
# There is a special character escape issue on line 91

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

Write-Output $pat | az devops login
az devops configure --defaults organization=$organization project=$project

$base64AuthInfo = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(":$($pat)"))
$authHeader = @{Authorization = 'Basic ' + $base64AuthInfo }

$attendees = (Get-Content $attendeesFile -Raw) | ConvertFrom-Json
$exercises = (Get-Content $exercisesFile -Raw) | ConvertFrom-Json

$organizationName = $organization.Split("/")[3]

Write-Output "Organization Url: $($organization)"
Write-Output "Organization Name: $($organizationName)"
Write-Output "Project Name: $($project)"


# Check to see if users are added to organization and add if need be
foreach($attendee in $attendees.attendees){

    # Check if user exists
    $checkAttendee = az devops user show --user $attendee.email

    if (!$checkAttendee) {

        Write-Output "Unable to find user $($attendee.email) in the $($organization) organization."

        $url = "https://vsaex.dev.azure.com/$($organizationName)/_apis/userentitlements?api-version=5.0-preview.2"

        $body = '{ "accessLevel": { "accountLicenseType": "none", "licensingSource": "msdn" }, "user": { "principalName": "' + $attendee.email + '", "subjectKind": "user" }, "projectEntitlements": [ { "group": { "groupType": "projectContributor" },"projectRef": {"id": "' + (az devops project show --project $($project) | ConvertFrom-Json).id + '" } } ] }'

        Invoke-RestMethod -Uri $url -headers $authHeader -Method POST -Body $body -ContentType 'application/json'
    }
}

# Exercise task generator
foreach($feature in $exercises.features){

    $exerciseFeature = az boards query --project $project `
        --wiql "SELECT [System.Id], [System.WorkItemType], [System.Title], [System.State], [System.AssignedTo] FROM WorkItems WHERE [Work Item Type] = 'Feature' AND [System.TeamProject] = '$project' AND [Title] = '$($feature.title)'" | ConvertFrom-Json

    if($exerciseFeature.Count -eq 0){

        $exerciseFeature = az boards work-item create `
            --title "$($feature.title)" `
            --description "$($feature.description)" `
            --type 'feature' | ConvertFrom-Json
    }

    foreach($pbi in $feature.pbis){

        foreach($attendee in $attendees.attendees){
            
            Write-Verbose $attendee.name

            $attendeeExerciseWorkItem = az boards query --project $project --wiql "SELECT [System.Id], [System.WorkItemType], [System.Title], [System.State], [System.AssignedTo] FROM WorkItems WHERE [Work Item Type] = 'product backlog item' AND [System.AssignedTo] = '$($attendee.email)' AND [System.TeamProject] = '$project' AND [Title] = '$($pbi.title)'" | ConvertFrom-Json

            if($attendeeExerciseWorkItem.Count -gt 0){

                Write-Verbose "Attendee: $($attendee.name) already has work item associated."

            } else {

                Write-Verbose "Doesn't Exists"
                
                $url = "https://dev.azure.com/$($organizationName)/$($project)/_apis/wit/workitems/`$Product Backlog Item?bypassRules=true&api-version=6.0"

                # Need to figure out how to handle special characters in the text fields

                #$attendeePBIWorkItem = Invoke-RestMethod -Uri $url -headers $authHeader `
                #    -Method POST `
                #    -Body "[{ 'op': 'add', 'path': '/fields/System.Title', 'from': null, 'value': '$($pbi.title)' }, `
                #            { 'op': 'add', 'path': '/fields/System.Description', 'from': null, 'value': '$($pbi.description)' }, `
                #            { 'op': 'add', 'path': '/fields/System.AssignedTo', 'from': null, 'value': '$($attendee.email)' }, `
                #            { 'op': 'add', 'path': '/fields/Microsoft.VSTS.Common.AcceptanceCriteria', 'from': null, 'value': '$($pbi.'acceptance criteria')'}]" `
                #    -ContentType 'application/json-patch+json'


                $attendeePBIWorkItem = Invoke-RestMethod -Uri $url -headers $authHeader `
                    -Method POST `
                    -Body "[{ 'op': 'add', 'path': '/fields/System.Title', 'from': null, 'value': '$($pbi.title)' }, `
                            { 'op': 'add', 'path': '/fields/System.AssignedTo', 'from': null, 'value': '$($attendee.email)' }]" `
                    -ContentType 'application/json-patch+json'

                az boards work-item relation add `
                    --id $attendeePBIWorkItem.id `
                    --relation-type parent `
                    --target-id $exerciseFeature[0].id

                foreach($task in $pbi.tasks){

                    Write-Verbose $task.title

                    # Work Item Tasks
                #    $attendeeTaskWorkItem = az boards work-item create `
                #        --title "$($task.title)" `
                #        --description "$($task.description)" `
                #        --assigned-to $attendee.email `
                #        --type 'task' | ConvertFrom-Json

                #    az boards work-item relation add `
                #        --id $attendeeTaskWorkItem.id `
                #        --relation-type parent `
                #        --target-id $attendeePBIWorkItem[0].id
                }
            }
        }
    }
}