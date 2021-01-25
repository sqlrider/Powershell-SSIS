function Export-SSISProjectSSISDB
{
param
(
    [Parameter(position=0, mandatory=$true)][string]$Instance,
    [Parameter(position=1, mandatory=$true)][string]$OutputDir
)


if(!(Test-Path $OutputDir))
{
    Write-Output "Error - invalid path specified in OutputDir"
 
    return
}

$testquery = "SELECT COUNT(*) AS 'Result' FROM sys.databases WHERE name = 'SSISDB'"

try
{
    $result = (Invoke-Sqlcmd -ServerInstance $Instance -Query $testquery -ConnectionTimeout 5 -QueryTimeout 5 -ErrorAction Stop).Result

    if($result -eq 0)
    {
        Write-Output "Error - no SSISDB present on instance or no permission to view it"
        
        return
    }
}
catch
{
    Write-Output "Error - failure connecting to instance"
    
    return
}

[System.Reflection.Assembly]::LoadWithPartialName("Microsoft.SqlServer.Management.IntegrationServices") | Out-Null

$SSISnamespace = "Microsoft.SqlServer.Management.IntegrationServices"

$connstring = "Data source=$($Instance);Initial Catalog=master;Integrated Security=SSPI;"
$sqlconn = New-Object System.Data.SqlClient.SqlConnection $connstring

$SSIS = New-Object $SSISnamespace".IntegrationServices" $sqlconn

$catalog = $SSIS.Catalogs["SSISDB"]

foreach($folder in $catalog.Folders)
{
    Set-Location -Path $outputdir

    New-Item -ItemType Directory -Name $folder.Name | Out-Null

    $folderpath = $outputdir + "\" + $folder.Name

    Set-Location -path $folderpath

    $projects = $folder.Projects

    if($projects.Count -gt 0)
    {
        foreach($project in $projects)
        {
            $projectpath = $folderpath + "\" + $project.Name + ".ispac"
            Write-Host "Exporting to $($projectpath) ...";
            [System.IO.File]::WriteAllBytes($projectpath, $project.GetProjectBytes())
        }
    }
}

Set-Location -Path $outputdir

<#
.SYNOPSIS
Exports all SSIS projects from an SSISDB database to a specified output directory

.DESCRIPTION
Retrieves all SSIS projects in .ispac format from an SSISDB database to a specified output directory, creating SSISDB folder structure.

.PARAMETER Instance
Specifies the SQL instance name

.PARAMETER OutputDir
Specifies the full output directory for SSISDB Folders/Projects to be exported to.

.OUTPUTS
No direct outputs from fuction - writes .ispac files.

.EXAMPLE
PS> Export-SSISProjectSSISDB -Instance SQLSSIS2014 -OutputDir "D:\DBA\SSIS\Export"

Exports all SSIS projects from instance SQLSSIS2014 as .ispac files to SSISDB Folder-named subfolders created in D:\DBA\SSIS\Export 
#>

}
