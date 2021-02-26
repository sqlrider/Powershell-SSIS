function Copy-SSISObjectParameters
{
param
(
    [Parameter(position=0, mandatory=$true)][string]$SourceServer,
    [Parameter(position=1, mandatory=$true)][string]$TargetServer,
    [Parameter(position=2, mandatory=$true)][string]$FolderName,
    [Parameter(position=3, mandatory=$true)][string]$ProjectName,
    [Parameter(position=4, mandatory=$false)][switch]$WhatIf
)

<#
.SYNOPSIS
Copies object parameter overrides from a SSIS project on a source instance to a target instance.

.DESCRIPTION
Copies object parameter overrides - that is, 'Edited' values on Configuration dialog - from a SSIS project 
on a source instance to a target instance. This includes both project and package-level overrides,
but does not include environment references, which are copied as part of the Copy-SSISEnvironments function.

.PARAMETER SourceServer
Specifies the source SQL instance name

.PARAMETER TargetServer
Specifies the target SQL instance name

.PARAMETER FolderName
Specifies the SSISDB folder the project is in. Case sensitive.

.PARAMETER ProjectName
Specifies the SSIS project (including packages) to copy the object parameter overrides from and to. Case sensitive.

.PARAMETER WhatIf
Outputs generated SQL statements only - does not execute them or make any other changes.

.OUTPUTS
No direct outputs from function - updates target server SSISDB object parameters

.EXAMPLE
PS> Copy-SSISObjectParameters -SourceServer SQLSSIS2014 -TargetServer SQLSSIS2017 -FolderName DailyETL -ProjectName LoadDailySales

Sets project/package parameter overrides in SSIS project DailyETL/LoadDailySales on server SQLSSIS2017 to the same as the project on SQLSSIS2014
#>



Import-Module SqlServer


### Check that folders and projects exist on both servers
$checkexistsquery = "SELECT 1 FROM [catalog].[folders] f
                            INNER JOIN [catalog].[projects] p
                                ON f.folder_id = p.folder_id
                            WHERE f.[name] = '$($FolderName)'
                                AND p.[name] = '$($ProjectName)'"

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
    Write-Output "Error: Folder or project doesn't exist on source server."
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
    Write-Output "Error: Folder or project doesn't exist on target server."
    return
}



### Get manually overridden parameter values (value_type V)
$getoverridevaluesquery = "SELECT op.object_type, op.object_name, op.parameter_name, op.data_type, op.default_value
                            FROM [catalog].[object_parameters] op
                            INNER JOIN [catalog].[projects] p
	                            ON op.project_id = p.project_id
                            INNER JOIN [catalog].[folders] f
	                            ON p.folder_id = f.folder_id
                            WHERE f.[name] = '$($FolderName)'
                            AND p.[name] = '$($ProjectName)'
                            AND op.value_type = 'V'
                            AND op.value_set = 1"

$overridevalues = Invoke-Sqlcmd -ServerInstance $SourceServer -Database SSISDB -Query $getoverridevaluesquery -ConnectionTimeout 3 -QueryTimeout 5 -ErrorAction Stop

foreach($overridevalue in $overridevalues)
{
    if($overridevalue.data_type -eq 'String')
    {
        if($overridevalue.object_type -eq 20) # Project parameter
        {
            $updateparameterquery = "EXEC [catalog].[set_object_parameter_value]
                                                                        @object_type = $($overridevalue.object_type),
                                                                        @folder_name = '$($FolderName)',
                                                                        @project_name = '$($ProjectName)',
                                                                        @parameter_name = '$($overridevalue.parameter_name)',
                                                                        @parameter_value = N'$($overridevalue.default_value)',
                                                                        @value_type = 'V'"
        }
        elseif($overridevalue.object_type -eq 30) # Package parameter
        {
            $updateparameterquery = "EXEC [catalog].[set_object_parameter_value]
                                                                        @object_type = $($overridevalue.object_type),
                                                                        @folder_name = '$($FolderName)',
                                                                        @project_name = '$($ProjectName)',
                                                                        @parameter_name = '$($overridevalue.parameter_name)',
                                                                        @parameter_value = N'$($overridevalue.default_value)',
                                                                        @object_name = '$($overridevalue.object_name)',
                                                                        @value_type = 'V'"
        }
    }
    elseif($overridevalue.data_type -eq 'Boolean')
    {
        if($overridevalue.default_value -eq 'True')
        {
            $bool_value = 1
        }
        else
        {
            $bool_value = 0
        }

        if($overridevalue.object_type -eq 20) # Project parameter
        {
            $updateparameterquery = "DECLARE @var BIT;
                                     SET @var = $($bool_value);
                                     EXEC [catalog].[set_object_parameter_value]
                                                                        @object_type = $($overridevalue.object_type),
                                                                        @folder_name = '$($FolderName)',
                                                                        @project_name = '$($ProjectName)',
                                                                        @parameter_name = '$($overridevalue.parameter_name)',
                                                                        @parameter_value = @var,
                                                                        @value_type = 'V'"
        }
        elseif($overridevalue.object_type -eq 30) # Package parameter
        {
            $updateparameterquery = "DECLARE @var BIT;
                                     SET @var = $($bool_value);
                                     EXEC [catalog].[set_object_parameter_value]
                                                                        @object_type = $($overridevalue.object_type),
                                                                        @folder_name = '$($FolderName)',
                                                                        @project_name = '$($ProjectName)',
                                                                        @parameter_name = '$($overridevalue.parameter_name)',
                                                                        @parameter_value = @var,
                                                                        @object_name = '$($overridevalue.object_name)',
                                                                        @value_type = 'V'"
        }
    }
    else # Integer or other number
    {
        if($overridevalue.object_type -eq 20) # Project parameter
        {
            $updateparameterquery = "EXEC [catalog].[set_object_parameter_value]
                                                                        @object_type = $($overridevalue.object_type),
                                                                        @folder_name = '$($FolderName)',
                                                                        @project_name = '$($ProjectName)',
                                                                        @parameter_name = '$($overridevalue.parameter_name)',
                                                                        @parameter_value = $($overridevalue.default_value),
                                                                        @value_type = 'V'"
        }
        elseif($overridevalue.object_type -eq 30) # Package parameter
        {
            $updateparameterquery = "EXEC [catalog].[set_object_parameter_value]
                                                                        @object_type = $($overridevalue.object_type),
                                                                        @folder_name = '$($FolderName)',
                                                                        @project_name = '$($ProjectName)',
                                                                        @parameter_name = '$($overridevalue.parameter_name)',
                                                                        @parameter_value = $($overridevalue.default_value),
                                                                        @object_name = '$($overridevalue.object_name)',
                                                                        @value_type = 'V'"
         }
    }

    if($WhatIf)
    {
        $updateparameterquery
    }
    else
    {
        try
        {
            Invoke-Sqlcmd -ServerInstance $TargetServer -Database SSISDB -Query $updateparameterquery -ConnectionTimeout 5 -QueryTimeout 5 -ErrorAction Stop
            Write-Output "Updated parameter $($overridevalue.parameter_name)"
        }
        catch
        {
            Write-Output "Error updating parameter $($overridevalue.parameter_name)"
            Write-Output $updateparameterquery
            Write-Output $error[0]
        }
    }

}


}