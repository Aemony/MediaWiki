#
# Module manifest for module 'MediaWiki'
#
# Created by:     Aemony
# Created on:     2020-06-10 22:14
# Filename:       MediaWiki.psd1
#

@{

  # Script module or binary module file associated with this manifest
  RootModule = 'MediaWiki.psm1'

  # Version number of this module.
  ModuleVersion = '0.9.0.0'

  # ID used to uniquely identify this module
  GUID = '880c4ed5-b652-4cc3-9f32-afea81917a47'

  # Author of this module
  Author = 'Aemony'

  # Company or vendor of this module
  CompanyName = ''

  # Copyright statement for this module
  Copyright = '(c) 2025 Aemony. All rights reserved.'

  # Description of the functionality provided by this module
  Description = 'PowerShell module for interfacing with MediaWiki API.'

  # Minimum version of the Windows PowerShell engine required by this module
  PowerShellVersion = '3.0'

  # Name of the Windows PowerShell host required by this module
  PowerShellHostName = ''

  # Minimum version of the Windows PowerShell host required by this module
  PowerShellHostVersion = ''

  # Minimum version of the .NET Framework required by this module
  DotNetFrameworkVersion = '2.0'

  # Minimum version of the common language runtime (CLR) required by this module
  CLRVersion = '2.0.50727'

  # Processor architecture (None, X86, Amd64, IA64) required by this module
  ProcessorArchitecture = 'None'

  # Modules that must be imported into the global environment prior to importing this module
  RequiredModules = @()

  # Assemblies that must be loaded prior to importing this module
  RequiredAssemblies = @('System.Web')

  # Script files (.ps1) that are run in the caller's environment prior to importing this module
  ScriptsToProcess = @()

  # Type files (.ps1xml) to be loaded when importing this module
  TypesToProcess = @()

  # Format files (.ps1xml) to be loaded when importing this module
  FormatsToProcess = @()

  # Modules to import as nested modules of the module specified in ModuleToProcess
  NestedModules = @()

  # Functions to export from this module
  #FunctionsToExport = '*' #For performance, list functions explicitly
  FunctionsToExport  = @('Add-*', 'Clear-MWSection', 'Clear-MWPage', 'Connect-MWSession', 'ConvertTo-*', 'Disconnect-MWSession', 'Find-*', 'Get-*', 'Invoke-*', 'Move-*', 'New-*', 'Remove-*', 'Rename-*', 'Search-*', 'Set-*', 'Show-*', 'Update-*')

  # Cmdlets to export from this module
  CmdletsToExport = '*'

  # Variables to export from this module
  VariablesToExport = '*'

  # Aliases to export from this module
  AliasesToExport = '*' #For performance, list alias explicitly

  # DSC class resources to export from this module.
  #DSCResourcesToExport = ''

  # List of all modules packaged with this module
  ModuleList = @()

  # List of all files packaged with this module
  FileList = @()

  # Private data to pass to the module specified in ModuleToProcess. This may also contain a PSData hashtable with additional module metadata used by PowerShell.
  PrivateData = @{

    #Support for PowerShellGet galleries.
    PSData = @{

      # Tags applied to this module. These help with module discovery in online galleries.
      Tags = @('MediaWiki')

      # A URL to the license for this module.
      LicenseUri = 'https://github.com/Aemony/MediaWiki/blob/main/LICENSE'

      # A URL to the main website for this project.
      ProjectUri = 'https://github.com/Aemony/MediaWiki/'

      # A URL to an icon representing this module.
      # IconUri = ''

      # ReleaseNotes of this module
      # ReleaseNotes = ''

    } # End of PSData hashtable

  } # End of PrivateData hashtable
}
