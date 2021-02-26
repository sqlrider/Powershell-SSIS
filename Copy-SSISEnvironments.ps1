function Copy-SSISEnvironments
{
param
(
    [Parameter(position=0, mandatory=$true)][string]$SourceServer,
    [Parameter(position=1, mandatory=$true)][string]$TargetServer,
    [Parameter(position=2, mandatory=$true)][string]$FolderName,
    [Parameter(position=3, mandatory=$false)][switch]$WhatIf
)

<#
.SYNOPSIS
Copies environments and references from one SSISDB folder to the same folder on another server

.DESCRIPTION
Copies environments - including variables, project references and object-variable links - from a source SSISDB folder to the same folder on a target server.
Works with string, numeric, boolean and encrypted string variables and relative project references.
Does not copy absolute references.

.PARAMETER SourceServer
Specifies the source SQL instance name

.PARAMETER TargetServer
Specifies the target SQL instance name

.PARAMETER FolderName
Specifies the SSISDB folder to copy the environment from and to. Case sensitive.

.PARAMETER WhatIf
Outputs generated SQL statements only - does not execute them or make any other changes.

.OUTPUTS
No direct outputs from function - updates target server SSISDB folder

.EXAMPLE
PS> Copy-SSISEnvironments -SourceServer SQLSSIS2014 -TargetServer SQLSSIS2017 -FolderName DailyETL

Copies environment data from SSISDB folder 'DailyETL' on server SQLSSIS2014 to server SQLSSIS2017
#>

Import-Module SqlServer

### Check that folder exists on both servers
$checkexistsquery = "SELECT 1 FROM [catalog].[folders] f
                     WHERE f.[name] = '$($FolderName)'"

try
{
    $check = Invoke-Sqlcmd -ServerInstance $SourceServer -Database SSISDB -Query $checkexistsquery -ConnectionTimeout 5 -QueryTimeout 5 -ErrorAction Stop
}
catch
{
    Write-Output "Error connecting to source server."
    Write-Output $error[0]
    return
}


if(!$check)
{
    Write-Output "Error: Folder $($FolderName) doesn't exist on source server."
    return
}

try
{
    $check = Invoke-Sqlcmd -ServerInstance $TargetServer -Database SSISDB -Query $checkexistsquery -ConnectionTimeout 5 -QueryTimeout 5 -ErrorAction Stop
}
catch
{
    Write-Output "Error connecting to target server."
    Write-Output $error[0]
    return
}

if(!$check)
{
    Write-Output "Error: Folder $($FolderName) doesn't exist on target server."
    return
}



$source_folder_id = 0
$target_folder_id = 0

$GetFolderIDQuery = "SELECT folder_id
                    FROM [catalog].folders
                    WHERE [name] = '$($FolderName)'"

# Get folder_id of source and target folders
$source_folder_id = (Invoke-Sqlcmd -ServerInstance $SourceServer -Database SSISDB -Query $GetFolderIDQuery -ConnectionTimeout 5 -QueryTimeout 5 -ErrorAction Stop).folder_id
$target_folder_id = (Invoke-Sqlcmd -ServerInstance $TargetServer -Database SSISDB -Query $GetFolderIDQuery -ConnectionTimeout 5 -QueryTimeout 5 -ErrorAction Stop).folder_id

$GetEnvironmentQuery = "SELECT environment_id, [name], [description]
                            FROM [catalog].environments
                            WHERE folder_id = '$($source_folder_id)'"

# Get environments from the source folder
$envs = (Invoke-Sqlcmd -ServerInstance $SourceServer -Database SSISDB -Query $GetEnvironmentQuery -ConnectionTimeout 5 -QueryTimeout 5 -ErrorAction Stop)


# Get environment references 
$GetEnvironmentRefsQuery = "SELECT p.project_id, p.[name] AS 'ProjectName', er.reference_type, er.environment_name
                            FROM [catalog].projects p
                            INNER JOIN [catalog].environment_references er
	                            ON p.project_id = er.project_id
                            WHERE p.folder_id = $($source_folder_id)"

try
{
    $env_refs = Invoke-Sqlcmd -ServerInstance $SourceServer -Database SSISDB -Query $GetEnvironmentRefsQuery -ConnectionTimeout 5 -QueryTimeout 5 -ErrorAction Stop
}
catch
{
    Write-Output "Error retrieving environment references"
    $GetEnvironmentRefsQuery
    Write-Output $error[0]
}

 
foreach($env in $envs)
{
    # Create environment on target server
    $CreateNewEnvironmentQuery = "EXEC [SSISDB].[catalog].[create_environment] @folder_name = '$($FolderName)', @environment_name = '$($env.name)', @environment_description = '$($env.description)'"

    if($WhatIf)
    {
        Write-Output $CreateNewEnvironmentQuery
    }
    else
    {
        try
        {
            Invoke-Sqlcmd -ServerInstance $TargetServer -Database SSISDB -Query $CreateNewEnvironmentQuery -ConnectionTimeout 5 -QueryTimeout 5 -ErrorAction Stop
            Write-Output "Created environment $($env.name)"
        }
        catch
        {
            Write-Output "Error creating environment"
            Write-Output $CreateNewEnvironmentQuery
            Write-Output $error[0]

            return
        }
    }

    # Get environment variables
    $GetEnvironmentVarsQuery = "SELECT variable_id, [name], sensitive, [type], [description], [value]
                                FROM [catalog].environment_variables
                                WHERE environment_id = $($env.environment_id)"

    $env_vars = (Invoke-Sqlcmd -ServerInstance $SourceServer -Database SSISDB -Query $GetEnvironmentVarsQuery -ConnectionTimeout 5 -QueryTimeout 5 -ErrorAction Stop)

    # Loop over environment variables
    foreach($env_var in $env_vars)
    {
        if($env_var.type -eq 'String')
        {
            # If variable is sensitive string, pull the encrypted value from [internal] table and decrypt it
            if($env_var.sensitive -eq 1)
            {
                $getencryptedvaluequery = "SELECT [internal].[get_value_by_data_type](DECRYPTBYKEYAUTOCERT(CERT_ID(N'MS_Cert_Env_' + CONVERT(NVARCHAR(20), [environment_id])), NULL, [sensitive_value]), [type]) AS DecryptedValue
                                            FROM [SSISDB].[internal].[environment_variables]
                                            WHERE variable_id = $($env_var.variable_id)"

                try
                {
                    $decryptedvalue = (Invoke-Sqlcmd -ServerInstance $SourceServer -Database SSISDB -Query $getencryptedvaluequery -ConnectionTimeout 3 -QueryTimeout 5 -ErrorAction Stop).DecryptedValue

                    $CreateEnvironmentVarQuery = "EXEC [SSISDB].[catalog].[create_environment_variable] @environment_name = '$($env.name)',
	                                                                                                    @folder_name = '$($FolderName)',
	                                                                                                    @variable_name = '$($env_var.name)',
	                                                                                                    @Sensitive = 1,
	                                                                                                    @data_type = '$($env_var.type)',
	                                                                                                    @description = '$($env_var.description)',
	                                                                                                    @value = N'$($decryptedvalue)'"
                }
                catch
                {
                    Write-Output "Failed to retrieve encrypted variable value"
                    $getencryptedvaluequery
                    Write-Output $error[0]
                }

            } 
            else
            {
                $CreateEnvironmentVarQuery = "EXEC [SSISDB].[catalog].[create_environment_variable] @environment_name = '$($env.name)',
	                                                                                                @folder_name = '$($FolderName)',
	                                                                                                @variable_name = '$($env_var.name)',
	                                                                                                @Sensitive = 0,
	                                                                                                @data_type = '$($env_var.type)',
	                                                                                                @description = '$($env_var.description)',
	                                                                                                @value = N'$($env_var.value)'"
            }
        }
        elseif($env_var.type -eq 'Boolean')
        {
            if($env_var.value -eq 'True')
            {
                $bool_value = 1
            }
            else
            {
                $bool_value = 0
            }

            $CreateEnvironmentVarQuery = "EXEC SSISDB.[catalog].[create_environment_variable] @environment_name = '$($env.name)',
	                                                                                            @folder_name = '$($FolderName)',
	                                                                                            @variable_name = '$($env_var.name)',
	                                                                                            @Sensitive = $([int]$env_var.sensitive),
	                                                                                            @data_type = '$($env_var.type)',
	                                                                                            @description = '$($env_var.description)',
	                                                                                            @value = $($bool_value)"

        }
        else
        {
            $CreateEnvironmentVarQuery = "EXEC SSISDB.[catalog].[create_environment_variable] @environment_name = '$($env.name)',
	                                                                                            @folder_name = '$($FolderName)',
	                                                                                            @variable_name = '$($env_var.name)',
	                                                                                            @Sensitive = $([int]$env_var.sensitive),
	                                                                                            @data_type = '$($env_var.type)',
	                                                                                            @description = '$($env_var.description)',
	                                                                                            @value = $($env_var.value)"
        }
        

        if($WhatIf)
        {
            Write-Output $CreateEnvironmentVarQuery
        }
        else
        {
            try
            {
                Invoke-Sqlcmd -ServerInstance $TargetServer -Database SSISDB -Query $CreateEnvironmentVarQuery -QueryTimeout 5 -ConnectionTimeout 5 -ErrorAction Stop
                Write-Output "Created variable $($env_var.name)"
            }
            catch
            {
                Write-Output "Error creating environment variable."
                Write-Output $CreateEnvironmentVarQuery
                Write-Output $error[0]
            }
        }
    }

    # Check if a reference exists for this environment, then for projects in target folder
    foreach($env_ref in $env_refs)
    {
        if($env_ref.reference_type -eq 'A')
        {
            Write-Warning "Warning - Absolute reference detected. Add manually. Project name $($env_ref.ProjectName)"
        }
        elseif($env_ref.environment_name -eq $env.name)
        {
            $CheckProjectExistsQuery = "SELECT 1 AS 'Result' WHERE EXISTS (SELECT [name]
                                                            FROM [catalog].projects
                                                            WHERE folder_id = $($target_folder_id)
                                                            AND name = '$($env_ref.ProjectName)')"

            #### Add reference for $env_ref.ProjectName

            try
            {
                $exists = (Invoke-SqlCmd -ServerInstance $TargetServer -Database SSISDB -Query $CheckProjectExistsQuery -ConnectionTimeout 5 -QueryTimeout 5 -ErrorAction Stop).Result

                if($exists -eq 1)
                {
                    # Add environment reference for this project
                    $CreateEnvironmentRefQuery = "EXEC [SSISDB].[catalog].[create_environment_reference] @environment_name = '$($env.name)',
														    @project_name = '$($env_ref.ProjectName)',
														    @folder_name = '$($FolderName)',
														    @reference_type = R,
                                                            @reference_id = NULL"
                    
                    if($WhatIf)
                    {
                        Write-Output $CreateEnvironmentRefQuery
                    }
                    else
                    {
                        try
                        {
                            Invoke-Sqlcmd -ServerInstance $TargetServer -Database SSISDB -Query $CreateEnvironmentRefQuery -ConnectionTimeout 5 -QueryTimeout 5 -ErrorAction Stop
                            Write-Output "Created reference between $($env_ref.ProjectName) and $($env.name)"


                            
                            #### Set object parameters to use environment variables where linked

                            $getobjectparamsquery = "SELECT object_type, [object_name], parameter_name, referenced_variable_name
                                        FROM catalog.object_parameters
                                        WHERE project_id = $($env_ref.project_id)
                                        AND value_type = 'R'"

                            $object_params = Invoke-Sqlcmd -ServerInstance $SourceServer -Database SSISDB -Query $getobjectparamsquery -ConnectionTimeout 3 -QueryTimeout 5 -ErrorAction Stop

                            foreach($object_param in $object_params)
                            {
                                if($object_param.object_type -eq 20) # Project parameter
                                {
                                    $setobjectparamquery = "EXEC [catalog].[set_object_parameter_value]
                                                                    @object_type = $($object_param.object_type),
                                                                    @folder_name = '$($FolderName)',
                                                                    @project_name = '$($env_ref.ProjectName)',
                                                                    @parameter_name = '$($object_param.parameter_name)',
                                                                    @parameter_value = '$($object_param.referenced_variable_name)',
                                                                    @value_type = 'R'"    
                                }
                                elseif($object_param.object_type -eq 30) # Package parameter
                                {
                                    $setobjectparamquery = "EXEC [catalog].[set_object_parameter_value]
                                            @object_type = $($object_param.object_type),
                                            @folder_name = '$($FolderName)',
                                            @project_name = '$($env_ref.ProjectName)',
                                            @parameter_name = '$($object_param.parameter_name)',
                                            @parameter_value = '$($object_param.referenced_variable_name)',
                                            @object_name = '$($object_param.object_name)',
                                            @value_type = 'R'"  
                                }

                                try
                                {
                                    Invoke-Sqlcmd -ServerInstance $TargetServer -Database SSISDB -Query $setobjectparamquery -ConnectionTimeout 3 -QueryTimeout 5 -ErrorAction Stop
                                    Write-Output "Linked parameter $($object_param.parameter_name) to env var $($object_param.referenced_variable_name)"
                                }
                                catch
                                {
                                    Write-Output "Error linking parameter."
                                    $setobjectparamquery
                                    Write-Output $error[0]
                                }

                            }

                        }
                        catch
                        {
                            Write-Output "Error creating environment reference."
                            $CreateEnvironmentRefQuery
                            Write-Output $error[0]
                        }
                    }
                }
            }
            catch
            {
                Write-Output $CheckProjectExistsQuery
                Write-Output $error[0]
            }


            if($WhatIf)
            {
                #### Set object parameters to use environment variables where linked

                $getobjectparamsquery = "SELECT object_type, [object_name], parameter_name, referenced_variable_name
                                        FROM catalog.object_parameters
                                        WHERE project_id = $($env_ref.project_id)
                                        AND value_type = 'R'"

                $object_params = Invoke-Sqlcmd -ServerInstance $SourceServer -Database SSISDB -Query $getobjectparamsquery -ConnectionTimeout 3 -QueryTimeout 5 -ErrorAction Stop

                foreach($object_param in $object_params)
                {
                    if($object_param.object_type -eq 20)
                    {
                        $setobjectparamquery = "EXEC [catalog].[set_object_parameter_value]
                                                        @object_type = $($object_param.object_type),
                                                        @folder_name = '$($FolderName)',
                                                        @project_name = '$($env_ref.ProjectName)',
                                                        @parameter_name = '$($object_param.parameter_name)',
                                                        @parameter_value = '$($object_param.referenced_variable_name)',
                                                        @value_type = 'R'"    
                    }
                    elseif($object_param.object_type -eq 30)
                    {
                        $setobjectparamquery = "EXEC [catalog].[set_object_parameter_value]
                                @object_type = $($object_param.object_type),
                                @folder_name = '$($FolderName)',
                                @project_name = '$($env_ref.ProjectName)',
                                @parameter_name = '$($object_param.parameter_name)',
                                @parameter_value = '$($object_param.referenced_variable_name)',
                                @object_name = '$($object_param.object_name)',
                                @value_type = 'R'"  
                    }

                    $setobjectparamquery
                }
            }

        }

    }

}

}