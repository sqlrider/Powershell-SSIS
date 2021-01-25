function Export-SSISPackageMSDB
{
param
(
    [Parameter(position=0, mandatory=$true)][string]$Instance,
    [Parameter(position=1, mandatory=$false)][string]$OutputDir,
    [Parameter(position=2, mandatory=$false)][switch]$DisplayOnly
)

Import-Module SqlServer

# Exit if OutputDir not specified without DisplayOnly switch
if(!$DisplayOnly)
{
    if(!$OutputDir)
    {
        Write-Output "Error - must specify OutputDir unless using DisplayOnly switch"

        return
    }
    if(!(Test-Path $OutputDir))
    {
        Write-Output "Error - invalid path specified in OutputDir"

        return
    }
}

# Sanitise path input
if(!$OutputDir.EndsWith('\'))
{
    $OutputDir = $OutputDir + '\'
}


$versionquery = "SELECT CAST(LEFT(CAST(SERVERPROPERTY('ProductVersion') AS VARCHAR(4000)),CHARINDEX('.',CAST(SERVERPROPERTY('ProductVersion') AS VARCHAR(4000))) - 1) AS DECIMAL(9,1)) AS 'Version'"

# Get SQL version, exit if cannot connect to instance to perform this query
try
{
    $version = (Invoke-Sqlcmd -ServerInstance $Instance -Query $versionquery -ConnectionTimeout 3 -QueryTimeout 3 -ErrorAction Stop).Version
}
catch
{
    Write-Output "Error connecting to server."
    Write-Output $error[0]
    
    return
}


# Set SSIS table names dependent on version 
if ($version -gt 9)
{
    Write-Debug "Version -gt 9"
    $SSISFoldersTable = 'sysssispackagefolders'
    $SSISPackageTable = 'sysssispackages'
}
else
{
    Write-Debug "Version -le 9"
    $SSISFoldersTable = 'sysdtspackagefolders90'
    $SSISPackageTable = 'sysdtspackages90'
}


$PackagesQuery = "WITH cte AS
                    (
                        SELECT CAST(foldername AS VARCHAR(MAX)) AS 'FolderPath', folderid
                        FROM msdb.dbo.$($SSISFoldersTable)
                        WHERE parentfolderid = '00000000-0000-0000-0000-000000000000'
                        UNION ALL
                        SELECT CAST(c.folderpath + '\' + f.foldername AS VARCHAR(MAX)), f.folderid
                        FROM msdb.dbo.$($SSISFoldersTable) f
                        INNER JOIN cte c 
                            ON c.folderid = f.parentfolderid
                    )
                    SELECT c.FolderPath, p.name, CAST(CAST(packagedata AS VARBINARY(MAX)) AS VARCHAR(MAX)) as 'pkg'
                    FROM cte c
                    INNER JOIN msdb.dbo.$SSISPackageTable p 
                        ON c.folderid = p.folderid
                    WHERE c.FolderPath NOT LIKE 'Data Collector%'
                    UNION
                    SELECT NULL, p.name, CAST(CAST(p.packagedata AS VARBINARY(MAX)) AS VARCHAR(MAX)) AS 'pkg'
                    FROM msdb.dbo.$($SSISFoldersTable) f
                    INNER JOIN msdb.dbo.$SSISPackageTable p
                        ON f.folderid = p.folderid
                    WHERE f.folderid = '00000000-0000-0000-0000-000000000000'"

$PackagesQueryDisplayOnly = "WITH cte AS
                            (
                                SELECT CAST(foldername AS VARCHAR(MAX)) AS 'FolderPath', folderid
                                FROM msdb.dbo.$($SSISFoldersTable)
                                WHERE parentfolderid = '00000000-0000-0000-0000-000000000000'
                                UNION ALL
                                SELECT CAST(c.FolderPath + '\' + f.foldername AS VARCHAR(MAX)), f.folderid
                                FROM msdb.dbo.$($SSISFoldersTable) f
                                INNER JOIN cte c 
                                    ON c.folderid = f.parentfolderid
                            )
                            SELECT c.FolderPath, p.name
                            FROM cte c
                            INNER JOIN msdb.dbo.$SSISPackageTable p 
                                ON c.folderid = p.folderid
                            WHERE c.FolderPath NOT LIKE 'Data Collector%'
                            UNION
                            SELECT NULL, p.name
                            FROM msdb.dbo.$($SSISFoldersTable) f
                            INNER JOIN msdb.dbo.$SSISPackageTable p
                                ON f.folderid = p.folderid
                            WHERE f.folderid = '00000000-0000-0000-0000-000000000000'"



Write-Output "SSIS Packages being retrieved;"

if($DisplayOnly)
{
    try
    {
        $packages = Invoke-Sqlcmd -ServerInstance $Instance -Database msdb -Query $PackagesQueryDisplayOnly -QueryTimeout 10 -ConnectionTimeout 10 -ErrorAction Stop

        $i = 0
        foreach($package in $packages)
        {
            Write-Host $package.Folderpath "/" $package.Name
            $i++
        }

        Write-Output "Total $($i) packages."
    }
    catch
    {
        Write-Output "Error retrieving packages."
        Write-Output $error[0]

        return
    }
}
else
{
    try
    {
        $packages = Invoke-Sqlcmd -ServerInstance $Instance -Database msdb -Query $PackagesQuery -MaxBinaryLength 100000 -MaxCharLength 10000000

        try
        {
            $i = 0
            foreach($package in $packages)
            {

                $package.pkg | Out-File -Force -Encoding ASCII -FilePath ("" + $($OutputDir) + $($package.Name) + ".dtsx")

                $i++
            }

            Write-Output "$($i) packages successfully written to $($OutputDir)."
        }
        catch
        {
            Write-Output "Error writing .dtsx files to specified location;"
            Write-Output $error[0]

            return
        }
    }
    catch
    {
        Write-Output "Error retrieving packages from MSDB;"
        Write-Output $error[0]

        return
    }
}

<#
.SYNOPSIS
Retrieves all SSIS packages from MSDB database.

.DESCRIPTION
Retrieves all SSIS packages from MSDB database, optionally saving the .dtsx package files to
a designated output.

.PARAMETER Instance
Specifies the SQL instance name

.PARAMETER OutputDir
Specifies the full output directory for SSIS packages to be exported to.

.PARAMETER DisplayOnly
Switch parameter that causes function to just output a list of SSIS package folders and names.

.OUTPUTS
No direct outputs from fuction - returns list of SSIS packages or writes .dtsx files.

.EXAMPLE
PS> Export-SSISPackageMSDB -Instance MYSQL2008SERVER -OutputDir "C:\DBA\SSIS\Export\"

Exports all SSIS packages from MYSQL2008SERVER as .dtsx files to C:\DBA\SSIS\Export\ 

.EXAMPLE
PS> Export-SSISPackageMSDB -Instance MYSQL2008SERVER -DisplayOnly

Displays list of SSIS packages on MYSQL2008SERVER
#>

}

