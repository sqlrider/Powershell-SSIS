# Powershell-SSIS

A collection of Powershell functions and scripts for use with SQL Server Integration Services.

- **Export-SSISPackageMSDB** - Exports SSIS packages as .dtsx files from MSDB repositories, with optional DisplayOnly filter to only list folders/packages
- **Export-SSISPackageSSISDB** - Exports SSIS projects from SSISDB repositories to .ispac files, creating a folder structure matching SSISDB
- **Copy-SSISEnvironments** - Copies SSISDB Environments and references from a folder on one instance to another
- **Copy-ObjectParameters** - Copies manually-edited object parameters from a project on one instance to another
