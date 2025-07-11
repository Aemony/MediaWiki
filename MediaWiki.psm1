<#
  .SYNOPSIS
    PowerShell module for interfacing with MediaWiki API.

  .DESCRIPTION
    PowerShell module for interfacing with a MediaWiki API endpoint.

  .NOTES
    Was design and tested towards the PCGamingWiki endpoint, so _a lot_
    of assumptions stem from that, such as supported properties and whatnot.

    Be sure to add/adjust if needed!
#>

Write-Host ""
Write-Host "---------------------------------------------------------------------------" -ForegroundColor Yellow
Write-Host ""
Write-Host "This PowerShell module allows you to connect to a MediaWiki API endpoint."   -ForegroundColor Yellow
Write-Host ""
Write-Host "         To establish a new connection: "                                    -ForegroundColor Yellow -NoNewline
                                         Write-Host "Connect-MWSession"                  -ForegroundColor DarkGreen
Write-Host "      To use/setup a persistent config: "                                    -ForegroundColor Yellow -NoNewline
                                         Write-Host "Connect-MWSession -Persistent"      -ForegroundColor DarkYellow
Write-Host "      To log in anonymously as a guest: "                                    -ForegroundColor Yellow -NoNewline
                                         Write-Host "Connect-MWSession -Guest"           -ForegroundColor DarkCyan
Write-Host "      To disconnect the active session: "                                    -ForegroundColor Yellow -NoNewline
                                         Write-Host "Disconnect-MWSession"               -ForegroundColor Gray
Write-Host "        To reset the persistent config: "                                    -ForegroundColor Yellow -NoNewline
                                         Write-Host "Connect-MWSession -Reset"           -ForegroundColor DarkGray
Write-Host ""
Write-Host "---------------------------------------------------------------------------" -ForegroundColor Yellow
Write-Host ""
































# --------------------------------------------------------------------------------------- #
#                                                                                         #
#                                         NOTEs                                           #
#                                                                                         #
# --------------------------------------------------------------------------------------- #

# - HashTable is used for the pure JSON responses, while PSObject is used for the
#     "end-user facing" objects.
#        
#     * ConvertFrom-JsonToHashtable handles all of the raw JSON objects.
#     * ConvertFrom-HashtableToPSObject handles all of the user-facing objects, and
#                                         renames the properties to PascalCase.

# - The MediaWiki API 'limit' parameter can at times be misleading as it does not ensure
#     that said amount of result is actually returned... So if you use a limit of say 100,
#       you may only get 69 results back, meaning you need to then make an additional
#         request just to attempt to get the missing requests... As such, it is easier to
#           request the maximum limit and then throw away any unused or unneeded trailing
#             entries...
#
#     * This also means the module is partially "wasteful" in that some cmdlets requests
#         _all_ of the data, _and then_ filters upon it. It makes for a simpler design
#           to implement, and reduces a huge amount of unnecessary repeated calls.


























# --------------------------------------------------------------------------------------- #
#                                                                                         #
#                                    GLOBAL VARIABLEs                                     #
#                                                                                         #
# --------------------------------------------------------------------------------------- #

# Global variable to hold the web session
$global:MWSession

# Script variable to indicate the location of the saved config file
$script:ConfigFileName = $env:LOCALAPPDATA + '\PowerShell\MediaWiki\config.json'

# Script variables used internally during runtime
$script:MWSessionGuest = $false
$script:MWSessionBot   = $false
$script:CSRFToken      = $null
$script:Config         = @{
  Protocol             = $null
  Wiki                 = $null
  API                  = $null
  URI                  = $null
  Persistent           = $false
}
$script:Cache          = @{
  SiteInfo             = $null
  UserInfo             = $null
  Namespaces           = $null
  RestrictionTypes     = @( )
  RestrictionLevels    = @( )
}

# Global configurations
$script:ProgressPreference = 'SilentlyContinue' # Suppress progress bar (speeds up Invoke-WebRequest by a ton)

# Enum used to indicate watchlist parameter value for cmdlets
enum WatchList
{
  NoChange
  Preferences
  Unwatch
  Watch
}

# Enum used to indicate search type for Find-MWPage
enum SearchType
{
  NearMatch
  Text
  Title
}

# PowerShell prefers using pascal case wherever is possible so let us rename as many property names as possible.
# This can potentially cause issues when something is renamed (e.g. Anon -> Anonymous)
$script:PropertyNamePascal    = @{
  <# API #>
  batchcomplete               = 'BatchComplete'
  query                       = 'Query'
  limits                      = 'Limits'
  duplicatefiles              = 'DuplicateFiles'
  allpages                    = 'AllPages'
  allimages                   = 'AllImages'
  pages                       = 'Pages'
  parse                       = 'Parse'
  warnings                    = 'Warnings'
  errors                      = 'Errors'
  code                        = 'Code'
  module                      = 'Module'
  docref                      = 'DocumentationReference'

  <# Need to be retained (for now) #>
  continue                    = 'continue'
  apcontinue                  = 'apcontinue'
  gapcontinue                 = 'gapcontinue'
  aicontinue                  = 'aicontinue'
  gaicontinue                 = 'gaicontinue'
  dfcontinue                  = 'dfcontinue'
  sroffset                    = 'sroffset'

  <# Site Info #>
  serverinfo                  = 'ServerInfo'
  name                        = 'Name'
  general                     = 'General'
  allcentralidlookupproviders = 'AllCentralIDLookupProviders'
  allunicodefixes             = 'AllUnicodeFixes'
  articlepath                 = 'ArticlePath'
  base                        = 'Base'
  case                        = 'Case'
  categorycollation           = 'CategoryCollation'
  centralidlookupprovider     = 'CentralIDLookupProvider'
  citeresponsivereferences    = 'CiteResponsiveReferences'
  dbtype                      = 'DatabaseType'
  dbversion                   = 'DatabaseVersion'
  fallback                    = 'Fallback'
  fallback8bitEncoding        = 'Fallback8bitEncoding'
  favicon                     = 'FavoriteIcon'
  fixarabicunicode            = 'FixArabicUnicode'
  fixmalayalamunicode         = 'FixMalayalamUnicode'
  galleryoptions              = 'GalleryOptions'
  captionLength               = 'CaptionLength'
  height                      = 'Height'
  imageHeight                 = 'ImageHeight'
  width                       = 'Width'
  imageWidth                  = 'ImageWidth'
  imagesPerRow                = 'ImagesPerRow'
  imagelimits                 = 'ImageLimits'
  imagewhitelistenabled       = 'ImageWhitelistEnabled'
  mode                        = 'Mode'
  showBytes                   = 'ShowBytes'
  showDimensions              = 'ShowDimensions'
  generator                   = 'Generator'
  interwikimagic              = 'InterwikiMagic'
  invalidusernamechars        = 'InvalidUsernameCharacters'
  lang                        = 'Language'
  langconversion              = 'LanguageConversion'
  legaltitlechars             = 'LegalTitleCharacters'
  linkprefix                  = 'LinkPrefix'
  linkprefixcharset           = 'LinkPrefixCharacterSet'
  linktrail                   = 'LinkTrail'
  logo                        = 'Logo'
  magiclinks                  = 'MagicLinks'
  ISBN                        = 'ISBN'
  PMID                        = 'PMID'
  RFC                         = 'RFC'
  mainpage                    = 'MainPage'
  mainpageisdomainroot        = 'MainPageIsDomainRoot'
  maxarticlesize              = 'MaximumArticleSize'
  maxuploadsize               = 'MaximumUploadSize'
  minuploadchunksize          = 'MinimumUploadChunkSize'
  misermode                   = 'MiserMode'
  phpsapi                     = 'PhpServerAPI'
  phpversion                  = 'PhpVersion'
  readonly                    = 'ReadOnly'
  rtl                         = 'RightToLeft'
  script                      = 'Script'
  scriptpath                  = 'ScriptPath'
  server                      = 'Server'
  servername                  = 'ServerName'
  sitename                    = 'SiteName'
  thumblimits                 = 'ThumbnailLimits'
  time                        = 'Time'
  timeoffset                  = 'TimeOffset'
  timezone                    = 'Timezone'
  titleconversion             = 'TitleConversion'
  uploadsenabled              = 'UploadsEnabled'
  variantarticlepath          = 'VariantArticlePath'
  wikiid                      = 'WikiID'
  writeapi                    = 'WriteAPI'

  <# Namespaces #>
  namespaces                  = 'Namespaces'
  canonical                   = 'CanonicalName'
  nonincludable               = 'IsNonIncludable'                # Renamed
  subpages                    = 'IsSubPagesAllowed'              # Renamed
  defaultcontentmodel         = 'DefaultContentModel'
  namespaceprotection         = 'NamespaceProtection'

  <# Protection #>
  restrictions                = 'Restrictions'
  cascadinglevels             = 'CascadingLevels'
  levels                      = 'Levels'
  semiprotectedlevels         = 'SemiProtectedLevels'
  types                       = 'Types'

  <# User Info #>
  userinfo                    = 'UserInfo'
  anon                        = 'Anonymous'                      # Longer
  messages                    = 'Messages'
  unreadcount                 = 'UnreadCount'
  editcount                   = 'EditCount'
  groups                      = 'Groups'
  rights                      = 'Rights'
  ratelimits                  = 'RateLimits'
  changetag                   = 'ChangeTag'
  emailuser                   = 'EmailUser'
  mailpassword                = 'MailPassword'
  purge                       = 'Purge'
  linkpurge                   = 'LinkPurge'
  renderfile                  = 'RenderFile'
 'renderfile-nonstandard'     = 'RenderFileNonStandard'
  stashedit                   = 'StashEdit'
  upload                      = 'Upload'
  user                        = 'User'
  ip                          = 'IP'
  hits                        = 'Hits'
  seconds                     = 'Seconds'

  <# Pages #>
  id                          = 'ID'                             # Potential conflict with PageID ?
  ns                          = 'Namespace'                      # Longer
  pageid                      = 'ID'                             # pageid -> ID
  title                       = 'Name'                           # title  -> Name
  displaytitle                = 'DisplayTitle'
  touched                     = 'LastModified'                   # Renamed
  revid                       = 'RevisionID'                     # Longer
  lastrevid                   = 'LastRevisionID'                 # Longer
  length                      = 'Length'
  links                       = 'Links'
  externallinks               = 'ExternalLinks'
  images                      = 'Images'
  sections                    = 'Sections'
  edit                        = 'Edit'
  new                         = 'New'
  exists                      = 'Exists'
  redirect                    = 'Redirect'
  missing                     = 'Missing'
  toclevel                    = 'TocLevel'
  anchor                      = 'Anchor'
  byteoffset                  = 'ByteOffset'
  fromtitle                   = 'FromTitle'
  index                       = 'Index'
  level                       = 'Level'
  line                        = 'Line'
  number                      = 'Number'
  template                    = 'Template'
  templates                   = 'Templates'
  category                    = 'Category'
  categories                  = 'Categories'
  categorieshtml              = 'CategoriesAsHtml'               # Renamed
  content                     = 'Content'                        # Dual-use! Content for pages, and "IsContentNamespace" for namespaces
  contentmodel                = 'ContentModel'
  pagelanguage                = 'PageLanguage'
  pagelanguagedir             = 'PageLanguageDirection'          # Renamed
  pagelanguagehtmlcode        = 'PageLanguageHtmlCode'


  <# Parse #>
  jsconfigvars                = 'JsConfigurationVariables'
  encodedjsconfigvars         = 'JsConfigurationVariablesAsJson' # Renamed
  headhtml                    = 'HeadAsHtml'                     # Renamed
  iwlinks                     = 'InterwikiLinks'                 # Renamed
  indicators                  = 'Indicators'
  prefix                      = 'Prefix'
  url                         = 'Url'
  langlinks                   = 'LanguageLinks'                  # Renamed
  limitreportdata             = 'LimitReportData'
  limitreporthtml             = 'LimitReportAsHtml'
  modules                     = 'Modules'
  modulescripts               = 'ModuleScripts'
  modulestyles                = 'ModuleStyles'
  parsedsummary               = 'ParsedSummary'
  parsetree                   = 'ParseTree'
  parsewarnings               = 'ParseWarnings'
  properties                  = 'Properties'
  text                        = 'Text'                           # Text / WikitextAsHtml
  wikitext                    = 'WikiText'
  transcludedin               = 'TranscludedIn'

  <# Images #>
  descriptionurl              = 'DescriptionUrl'
  imageinfo                   = 'ImageInfo'
  imagerepository             = 'ImageRepository'
  bitdepth                    = 'BitDepth'
  archivename                 = 'ArchiveName'
  canonicaltitle              = 'CanonicalName'
  comment                     = 'Comment'
  parsedcomment               = 'ParsedComment'
  metadata                    = 'Metadata'
  commonmetadata              = 'CommonMetadata'
  hidden                      = 'Hidden'
  source                      = 'Source'
  value                       = 'Value'
  html                        = 'Html'
  mediatype                   = 'MediaType'
  duration                    = 'Duration'
  mime                        = 'MIME'
  sha1                        = 'SHA1'
  userid                      = 'UserID'
  badfile                     = 'BadFile'
  
  # https://www.mediawiki.org/wiki/Extension:CommonsMetadata ?
  extmetadata                 = 'ExtensionMetadata'              # ExtendedMetadata? ExtensionMetadata? ExternalMetadata? ExtractedMetadata?
  DateTime                    = 'DateTime'
  ObjectName                  = 'ObjectName'

  <# Listing #>
  type                        = 'Type'
  sortkey                     = 'SortKey'
  sortkeyprefix               = 'SortKeyPrefix'

  <# Search #>
  search                      = 'Search'
  size                        = 'Size'
  snippet                     = 'Snippet'
  timestamp                   = 'Timestamp'
  wordcount                   = 'WordCount'
  searchinfo                  = 'SearchInfo'
  totalhits                   = 'TotalHits'

  <# Debug #>
  curtimestamp                = 'ServerTimestamp'                # Current server timestamp / Retrieved
}





























# --------------------------------------------------------------------------------------- #
#                                                                                         #
#                                     HELPER CMDLETs                                      #
#                                                                                         #
# --------------------------------------------------------------------------------------- #

#region Copy-Object
function Copy-Object
{
<#
  .SYNOPSIS
    Helper function to do a deep copy on input objects.
  .DESCRIPTION
    In various situations PowerShell can pass a reference to another object instead of
    passing a copy of the object. This can result in situations where modifying the data
    in a later function or call also modifies the original data. This helper function
    works around the issue by forcing a deep copy of the input objects to ensure no
    references to the original copy remain.

    Note that depending on the complexity of the input object, this action can be slow
    and should therefor only be used when necessary.
  .PARAMETER InputObject
    The input object to perform a deep copy of. The object will be traversed to the
    depth specified by the -Depth parameter (default 100).
  .PARAMETER Depth
    The depth of the object to traverse when doing the deep copy. Defaults to 100.
  .LINK
    https://stackoverflow.com/a/57045268
  .NOTES
    Licensed by CC BY-SA 4.0
    https://creativecommons.org/licenses/by-sa/4.0/
#>
  [CmdletBinding()]
  param (
    [Parameter(ValueFromPipeline)]
    [Object[]]$InputObject,
    
    [Parameter()]
    [uint32] $Depth = 100
  )

  Begin { }

  Process {
    $Clones = ForEach ($Object in $InputObject) {
      $Object | ConvertTo-Json -Compress -Depth $Depth | ConvertFrom-Json
    }

    return $Clones
  }

  End { }
}
#endregion

#region ConvertFrom-JsonToHashtable
<#
  .SYNOPSIS
    Helper function to take a JSON string and turn it into a hashtable
  .DESCRIPTION
    The ConvertFrom-Json method does not have the -AsHashtable switch in Windows PowerShell,
    which makes it inconvenient to convert JSON to hashtable.
  .LINK
    https://github.com/abgox/ConvertFrom-JsonToHashtable
  .NOTES
    MIT License

    Copyright (c) 2024-present abgox <https://github.com/abgox | https://gitee.com/abgox>

    Permission is hereby granted, free of charge, to any person obtaining a copy
    of this software and associated documentation files (the "Software"), to deal
    in the Software without restriction, including without limitation the rights
    to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
    copies of the Software, and to permit persons to whom the Software is
    furnished to do so, subject to the following conditions:

    The above copyright notice and this permission notice shall be included in all
    copies or substantial portions of the Software.

    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
    IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
    FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
    AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
    LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
    OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
    SOFTWARE.
#>
function ConvertFrom-JsonToHashtable
{
  param (
      [Parameter(ValueFromPipeline = $true)]
      [string]$InputObject
  )

  $Results = [regex]::Matches($InputObject, '\s*"\s*"\s*:')
  foreach ($Result in $Results)
  { $InputObject = $InputObject -replace $Result.Value, "`"empty_key_$([System.Guid]::NewGuid().Guid)`":" }
  $InputObject = [regex]::Replace($InputObject, ",`n?(\s*`n)?\}", "}")

  function ProcessArray ($Array)
  {
    $NestedArray = @()
    foreach ($Item in $Array)
    {
      if ($Item -is [System.Collections.IEnumerable] -and $Item -isnot [string])
      { $NestedArray += , (ProcessArray $Item) }
      elseif ($Item -is [System.Management.Automation.PSCustomObject])
      { $NestedArray += ConvertToHashtable $Item }
      else
      { $NestedArray += $Item }
    }
    return , $NestedArray
  }

  function ConvertToHashtable ($Object)
  {
    $Hash = [ordered]@{}

    if ($Object -is [System.Management.Automation.PSCustomObject])
    {
      foreach ($Property in $Object | Get-Member -MemberType Properties)
      {
        $Key   = $Property.Name # Key
        $Value = $Object.$Key   # Value

        # Handle array (preserve nested structure)
        if ($Value -is [System.Collections.IEnumerable] -and $Value -isnot [string])
        { $Hash[[object] $Key] = ProcessArray $Value }

        # Handle object
        elseif ($Value -is [System.Management.Automation.PSCustomObject])
        { $Hash[[object] $Key] = ConvertToHashtable $Value }

        else
        { $Hash[[object] $Key] = $Value }
      }
    }

    else
    { $Hash = $Object }

    $Hash # Do not convert to [PSCustomObject] and output. # [PSCustomObject]
  }

  # Recurse
  ConvertToHashtable ($InputObject | ConvertFrom-Json)
}
#endregion

#region ConvertFrom-HashtableToPSObject
# Based on ConvertFrom-JsonToHashtable just above
function ConvertFrom-HashtableToPSObject
{
  param (
    [Parameter(Mandatory, ValueFromPipeline)]
    [AllowNull()]
    $InputObject
  )

  function ProcessArray ($Array)
  {
    $NestedArray = @()
    #$NestedArray = [ordered] @{}

    foreach ($Item in $Array)
    {
      if ($Item -is [System.Collections.Specialized.OrderedDictionary])
      { $NestedArray += ConvertToPSObject $Item }
      elseif ($Item -is [System.Collections.IEnumerable] -and $Item -isnot [string])
      { $NestedArray += , (ProcessArray $Item) }
      else
      { $NestedArray += $Item }
    }
    return , $NestedArray
  }

  function ConvertToPSObject ($Object)
  {
    $Hash = [ordered] @{}

    if ($Object -is [System.Collections.Specialized.OrderedDictionary])
    {
      foreach ($Property in $Object.GetEnumerator())
      {
        $Key   = $Property.Name # Key
        $Value = $Object.$Key   # Value
        $NewName = $PropertyNamePascal[$Key]

        if ($NewName)
        { $Key = $NewName }
        elseif ($Key -notmatch "^[-]?[\d]+$")
        { Write-Warning "Missing pascal case for: $Key" }

        # Handle array (preserve nested structure)
        if ($Value -is [System.Collections.IEnumerable] -and $Value -isnot [string])
        { $Hash[[object] $Key] = ProcessArray $Value }

        # Handle object
        elseif ($Value -is [System.Collections.Specialized.OrderedDictionary])
        { $Hash[[object] $Key] = ConvertToPSObject $Value }

        else
        { $Hash[[object] $Key] = $Value }
      }
    }

    else
    { $Hash = $Object }

    [PSCustomObject]$Hash # Convert to [PSCustomObject] and output
  }

  # Recurse
  ConvertToPSObject ($InputObject)
}
#endregion

#region ConvertTo-MWEscapedString
function ConvertTo-MWEscapedString
{
<#
  .SYNOPSIS
    Conversion helper used to escape a subset of characters to their HTML entities.
  .DESCRIPTION
    Some characters ("|=[]" etc) are used by the wikitext parser of MediaWiki and can
    therefor run into issues if these characters are used in some places. This helper
    converts such characters to their HTML entities, bypassing the issue.
  .PARAMETER InputObject
    A string or an array of strings to perform the character escaping on.
  .EXAMPLE
    ConvertTo-MWEscapedString -InputObject $WebsiteTitle
#>
  [CmdletBinding()]
  param (
    <#
      Core parameters
    #>
    [Parameter(Mandatory, ValueFromPipeline, Position=0)]
    [string[]]$InputObject
  )

  Begin { }

  Process
  {
      # https://www.thoughtco.com/html-code-for-common-symbols-and-signs-2654021
    $Buffer = $InputObject | ForEach-Object {
      $Escaped = $_
      $Escaped = $Escaped.Replace('=', '&#61;' )
      $Escaped = $Escaped.Replace('[', '&#91;' )
      $Escaped = $Escaped.Replace(']', '&#93;' )
      $Escaped = $Escaped.Replace('|', '&#124;')
      $Escaped
    }

    return $Buffer
  }

  End { }
}
#endregion

#region ConvertTo-MWNamespaceID
function ConvertTo-MWNamespaceID
{
<#
  .SYNOPSIS
    Conversion helper used to convert namespace names into their relevant IDs.
  .DESCRIPTION
    When used to validate a [string] parameter, the input object will only be accepted if it
    matches a positive namespace ID or name registered on the MediaWiki site.
  .PARAMETER InputObject
    An array of strings containing either valid namespace IDs or names, where the names will
    be converted into their respective IDs.
  .EXAMPLE
    $Namespace = ConvertTo-MWNamespaceID $Namespace
#>
  [CmdletBinding()]
  param (
    [Parameter(Mandatory)]
    [AllowEmptyString()]
    [AllowNull()]
    [string[]]$InputObject,

    # Some API calls only support a single namespace
    [switch]$Single,

    # Negative namespaces (Media and Special) are special and seldom used/supported through the API.
    [switch]$IncludeNegative
  )

  Begin { }

  Process
  {
    [string[]]$Buffer = @()

    if ($null -ne $InputObject.Count)
    {
      # Does the array include a wildcard?
      # If so, include all of the namespaces the site supports
      if ($InputObject -contains '*')
      {
        if ($IncludeNegative)
        { $Buffer = (Get-MWNamespace -IncludeNegative).ID }
        else
        { $Buffer = (Get-MWNamespace).ID }
      }
      
      # Test each element in the array
      else
      {
        ForEach ($NS in $InputObject)
        {
          # Try-Catch to suppress exception thrown when
          # casting a non-numeric string to int32
          try {
                if ($tmp = Get-MWNamespace -NamespaceName $NS)
            { $Buffer += $tmp.ID }
            elseif ($tmp = Get-MWNamespace -NamespaceID   $NS)
            { $Buffer += $tmp.ID }
          } catch { }
        }
      }
    }

    $Buffer = $Buffer | Select-Object -Unique

    if ($Buffer.Count -gt 0)
    {
      if ($Single)
      { return $Buffer[0] }
      else
      { return $Buffer -join '|' }
    }
    else
    { return '' }
  }

  End { }
}
#endregion

#region Rename-PropertyName
function Rename-PropertyName
{
<#
  .SYNOPSIS
    Helper function used to rename specific property names to something else.
  .DESCRIPTION
    When used to validate a [string] parameter, the input object will only be allowed if it
    matches a positive namespace ID or name registered on the MediaWiki site.
  .PARAMETER InputObject
    An object to perform the validation on.
  .EXAMPLE
#>
  [CmdletBinding()]
  param (
    [Parameter(Mandatory, Position=0)]
    $InputObject,
    [Parameter(Mandatory, Position=1)]
    $PropertyName,
    [Parameter(Mandatory, Position=2)]
    $NewPropertyName
  )

  $Value = $InputObject.$PropertyName
  $InputObject.PSObject.Properties.Remove($PropertyName)
  $InputObject | Add-Member -MemberType NoteProperty -Name $NewPropertyName -Value $Value

  return $InputObject
}
#endregion

#region Test-MWNamespace
function Test-MWNamespace
{
<#
  .SYNOPSIS
    Validation helper used to ensure the input is a valid namespace name or ID.
  .DESCRIPTION
    When used to validate a [string] parameter, the input object will only be allowed if it
    matches a positive namespace ID or name registered on the MediaWiki site.
  .PARAMETER InputObject
    An object to perform the validation on.
  .EXAMPLE
    [ValidateScript({ Test-MWNamespace -InputObject $PSItem })]
    [string[]]$Namespace,
#>
  [CmdletBinding()]
  param (
    [Parameter(Mandatory)]
    $InputObject,

    [switch]$AllowWildcard
  )

  if (($AllowWildcard -and $InputObject -contains '*') -or
      ((Get-MWNamespace).ID   -contains $InputObject)  -or
      ((Get-MWNamespace).Name -contains $InputObject))
  { $true }
  else
  { throw ("'$InputObject' is not a valid namespace; see `"Get-MWNamespace`" for allowed values.") }
}
#endregion

#region Test-MWProtectionLevel
function Test-MWProtectionLevel
{
<#
  .SYNOPSIS
    Validation helper used to ensure the input is a valid protection level.
  .DESCRIPTION
    When used to validate a [string] parameter, the input object will only
    be allowed if it matches a valid protection level.
  .PARAMETER InputObject
    An object to perform the validation on.
  .EXAMPLE
    [ValidateScript({ Test-MWProtectionLevel -InputObject $PSItem })]
    [string[]]$ProtectionLevel
#>
  [CmdletBinding()]
  param (
    [Parameter(Mandatory)]
    $InputObject
  )

  if ($InputObject -in $script:Cache.RestrictionLevel)
  { $true }
  else
  { throw ('The argument "' + $InputObject + '" does not belong to the set "' + ($script:Cache.RestrictionLevel -join ',') + '". Supply an argument that is in the set and then try the command again.') }
}
#endregion

#region Test-MWProtectionType
function Test-MWProtectionType
{
<#
  .SYNOPSIS
    Validation helper used to ensure the input is a valid protection type.
  .DESCRIPTION
    When used to validate a [string] parameter, the input object will only
    be allowed if it matches a valid protection type.
  .PARAMETER InputObject
    An object to perform the validation on.
  .EXAMPLE
    [ValidateScript({ Test-MWProtectionType -InputObject $PSItem })]
    [string[]]$ProtectionType
#>
  [CmdletBinding()]
  param (
    [Parameter(Mandatory)]
    $InputObject
  )

  if ($InputObject -in $script:Cache.RestrictionType)
  { $true }
  else
  { throw ('The argument "' + $InputObject + '" does not belong to the set "' + ($script:Cache.RestrictionType -join ',') + '". Supply an argument that is in the set and then try the command again.') }
}
#endregion

#region Test-MWResultSize
function Test-MWResultSize
{
<#
  .SYNOPSIS
    Validation helper used to ensure the input is an 'Unlimited' string or a positive integer.
  .DESCRIPTION
    When used to validate a [string] parameter, the input object will only be accepted if it is
    a positive integer or 'Unlimited' is specified.
  .PARAMETER InputObject
    An object to perform the validation on.
  .EXAMPLE
    [ValidateScript({ Test-MWResultSize -InputObject $PSItem })]
    [string]$ResultSize = 1000,
#>
  [CmdletBinding()]
  param (
    [Parameter(Mandatory)]
    $InputObject
  )

  if (([string]$InputObject -eq 'Unlimited') -or ([int32]$InputObject -gt 0))
  { $true }
  else
  { throw ('Specify a valid number of results to retrieve, or "Unlimited" to retrieve all.') }
}
#endregion

#region Write-MWWarningResultSize
function Write-MWWarningResultSize
{
<#
  .SYNOPSIS
    Warning helper used to throw a common warning message when there are more results available
  .DESCRIPTION
    The input object is used to validate if more data is available, and if so this warning helper
    throws an appropriate warning based on the default result size and the given result size.
  .PARAMETER InputObject
    Used to indicate if more data is available. The variable is checked against $null so any
    non-null value will be handled as if more data is available.
  .PARAMETER DefaultSize
    The default result size of the caller function, when not specified by an input parameter.
  .PARAMETER ResultSize
    The actual result size value of the caller function, typically specified through an input parameter.
  .EXAMPLE
    Write-MWWarningResultSize -InputObject $Body.apcontinue -DefaultSize 1000 -ResultSize $ResultSize
#>
  [CmdletBinding()]
  param (
    [Parameter(Mandatory)]
    [AllowNull()]
    $InputObject,
    [Parameter(Mandatory)]
    [uint32]$DefaultSize,
    [Parameter(Mandatory)]
    [uint32]$ResultSize
  )

  if ($InputObject)
  {
    $Message = if ($ResultSize -eq $DefaultSize) { "By default, only the first $DefaultSize items are returned." }
                                            else { 'There are more results available than currently displayed.'  }
    $Message += ' Use the ResultSize parameter to specify the number of items returned. To return all items, specify "-ResultSize Unlimited".'
    Write-Warning $Message
  }
}
#endregion
































# --------------------------------------------------------------------------------------- #
#                                                                                         #
#                                         CMDLETs                                         #
#                                                                                         #
# --------------------------------------------------------------------------------------- #

#region Clear-MWSession
function Clear-MWSession
{
  [CmdletBinding()]
  param ( )

  Begin { }

  Process { }

  End
  {
    # Clear the variables of their current values
    if ($null -ne $global:MWSession)
    { Clear-Variable MWSession -Scope Global }

    if ($null -ne $script:MWSessionGuest)
    { Clear-Variable MWSessionGuest -Scope Script }

    if ($null -ne $script:MWSessionBot)
    { Clear-Variable MWSessionBot -Scope Script }

    if ($null -ne $script:CSRFToken)
    { Clear-Variable CsrfToken -Scope Script }

    if ($null -ne $script:Config)
    { Clear-Variable Config -Scope Script }

    if ($null -ne $script:Cache)
    { Clear-Variable Cache -Scope Script }

    # Reset the variables to their default values
    $global:MWSession      = $null
    
    $script:MWSessionGuest = $false
    $script:MWSessionBot   = $false
    $script:CSRFToken      = $null

    $script:Config         = @{
      Protocol             = $null
      Wiki                 = $null
      API                  = $null
      URI                  = $null
      Persistent           = $false
    }

    $script:Cache          = @{
      SiteInfo             = $null
      UserInfo             = $null
      Namespaces           = $null
      RestrictionTypes     = @( )
      RestrictionLevels    = @( )
    }
  }
}
#endregion

#region Connect-MWSession
function Connect-MWSession
{
  [CmdletBinding()]
  param (
    [switch]$Persistent,
    [switch]$Guest,
    [switch]$Reset
  )

  Begin
  {
    $TempConfig = $null

    if ($Reset)
    {
      if ((Test-Path $script:ConfigFileName) -eq $true)
      { Remove-Item $script:ConfigFileName }
    }

    if ($Persistent -and (Test-Path $script:ConfigFileName) -eq $true)
    {
      if ($Guest)
      { Write-Verbose "Using stored server configuration, but in an anonymous session." }
      else
      { Write-Verbose "Using stored credentials. Use -Reset to recreate or bypass the stored credentials." }

      Try
      {
        # Try to load the config file.
        $TempConfig = Get-Content $script:ConfigFileName -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop

        # Unset to force an anonymous session
        if ($Guest)
        {
          $TempConfig.Username = $null 
          $TempConfig.Password = $null
        } else {
          # Try to convert the hashed password. This will only work on the same machine that the config file was created on.
          $TempConfig.Password = ConvertTo-SecureString $TempConfig.Password -Key (3, 4, 2, 3, 56, 34, 254, 222, 1, 1, 2, 23, 42, 54, 33, 233, 1, 34, 2, 7, 6, 5, 35, 43) -ErrorAction Stop
        }
      } Catch [System.Management.Automation.ItemNotFoundException], [System.ArgumentException] {
        # Handle corrupt config file
        Write-Warning "The stored configuration could not be found or was corrupt.`n"
        $TempConfig = $null
      } Catch [System.Security.Cryptography.CryptographicException] {
        # Handle broken password
        Write-Warning "The password in the stored configuration could not be read."
        $TempConfig = $null
      } Catch {
        # Unknown exception
        Write-Warning "Unknown error occurred when trying to read stored configuration."
        $TempConfig = $null
      }
    }

    if ($null -eq $TempConfig)
    {
      if (!($APIEndpoint = Read-Host 'Type in the full URI to the API endpoint [https://www.pcgamingwiki.com/w/api.php]')) { $APIEndpoint = 'https://www.pcgamingwiki.com/w/api.php' }
      $Split    = ($APIEndpoint -split '://')
      $Split2   = ($Split[1] -split '/')
      $Protocol = $Split[0] + '://'
      $API      = $Split2[-1]
      $Wiki     = $APIEndpoint -replace $Protocol, '' -replace $API, ''

      $Username = Read-Host 'Username'
      [SecureString]$SecurePassword = Read-Host 'Password' -AsSecureString

      $TempConfig = @{
        Protocol  = $Protocol
        Wiki      = $Wiki
        API       = $API
        Username  = $Username
        Password  = if ($SecurePassword.Length -eq 0) { '' } else { $SecurePassword | ConvertFrom-SecureString -Key (3, 4, 2, 3, 56, 34, 254, 222, 1, 1, 2, 23, 42, 54, 33, 233, 1, 34, 2, 7, 6, 5, 35, 43) }
      }

      if ($Persistent)
      {
        # Create the file first using New-Item with -Force parameter so missing directories are also created.
        New-Item -Path $script:ConfigFileName -ItemType "file" -Force | Out-Null

        # Output the config to the recently created file
        $TempConfig | ConvertTo-Json | Out-File $script:ConfigFileName
      }

      # Convert the hashed password back to a SecureString
      if ($SecurePassword.Length -gt 0)
      { $TempConfig.Password = $SecurePassword }
    }

    $script:Config = @{
      Protocol     = $TempConfig.Protocol
      Wiki         = $TempConfig.Wiki
      API          = $TempConfig.API
      URI          = $TempConfig.Protocol + $TempConfig.Wiki + $TempConfig.API
      Persistent   = $Persistent
    }

    # Authenticated login
    if ((-not [string]::IsNullOrEmpty($TempConfig.Username)) -and (-not [string]::IsNullOrEmpty($TempConfig.Password)))
    {
      $PlainPassword = $null

      if ($TempConfig.Password.Length -gt 0)
      {
        $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($TempConfig.Password)
        $PlainPassword = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
      }


      $Body = [ordered]@{
        action     = 'query'
        meta       = 'tokens'
        type       = 'login'
      }
      
      $Response = Invoke-MWApiRequest -Body $Body -Method GET -IgnoreDisconnect -NoAssert -SessionVariable global:MWSession

      if ($Response)
      {
        $Body = [ordered]@{
          action     = 'login'
          lgname     = $TempConfig.Username
          lgpassword = $PlainPassword
          lgtoken    = $Response.query.tokens.logintoken
        }

        $Response = Invoke-MWApiRequest -Body $Body -Method POST -IgnoreDisconnect -NoAssert

        if ($Response.login.result -ne 'Success')
        { Write-Warning -Message "[$($Response.login.result)] $($Response.login.reason)" }
        else
        { $script:MWSessionGuest = $false }
      }
    }
    
    # Anonymous login
    else {
      # Only warn if we have not explicitly used an anonymous session
      if ($Guest -eq $false)
      { Write-Warning "User credentials have not been specified; falling back to guest session." }

      $Body = [ordered]@{
        action = 'query'
        meta   = 'userinfo'
      }

      $Response = Invoke-MWApiRequest -Body $Body -Method GET -IgnoreDisconnect -SessionVariable global:MWSession

      if ($Response)
      {
        if ($null -eq $Response.query.userinfo.anon)
        { Write-Warning "You are not an anonyumous user." }
        else
        { $script:MWSessionGuest = $true }
      }
    }
  }

  Process { }

  End
  {
    $SecurePassword = $null
    $PlainPassword  = $null
    $TempConfig     = $null

    if ($BSTR)
    { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($BSTR) }

    # Cache site information (restrictions, namespaces, etc)
    $script:Cache.SiteInfo = Get-MWSiteInfo

    # Cache user information (rate limits etc)
    $script:Cache.UserInfo = Get-MWUserInfo

    Write-Host "Welcome " -ForegroundColor Yellow -NoNewline

    if ($script:Cache.UserInfo.LatestContribution)
    { Write-Host "back " -ForegroundColor Yellow -NoNewline }

    Write-Host $script:Cache.UserInfo.Name -ForegroundColor DarkGreen -NoNewline
    Write-Host "!" -ForegroundColor Yellow -NoNewline

    if ($script:Cache.UserInfo.LatestContribution)
    {
      Write-Host " Your latest contribution was on " -ForegroundColor Yellow -NoNewline
      Write-Host "$([datetime]$script:Cache.UserInfo.LatestContribution)." -ForegroundColor DarkYellow -NoNewline
    }

    Write-Host # NewLine

    if ($script:Cache.UserInfo.Messages)
    {
      Write-Host "You have "   -ForegroundColor Yellow     -NoNewline
      Write-Host "unread"      -ForegroundColor DarkYellow -NoNewline
      Write-Host " messages! " -ForegroundColor Yellow     -NoNewline
    }
    
    if ($script:Cache.UserInfo.UnreadCount)
    {
      Write-Host "There are " -ForegroundColor Yellow -NoNewline
      Write-Host $script:Cache.UserInfo.UnreadCount -ForegroundColor DarkYellow -NoNewline
      Write-Host " unread pages on your watchlist." -ForegroundColor Yellow -NoNewline
    }

    Write-Host # NewLine

    $script:MWSessionBot = ($null -ne ($script:Cache.UserInfo.Groups | Where-Object { $_ -eq 'bot' }))
  }
}
#endregion

#region ConvertTo-MWParsedOutput
function ConvertTo-MWParsedOutput
{
  [CmdletBinding(DefaultParameterSetName = 'Text')]
  param (
    <#
      Core parameters
    #>
    [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName, ParameterSetName = 'Text', Position=0)]
    [ValidateNotNullOrEmpty()]
    [string]$Text,

    [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName, ParameterSetName = 'Summary', Position=0)]
    [ValidateNotNullOrEmpty()]
    [string]$Summary,

    [Parameter(ValueFromPipelineByPropertyName)]
    [ValidateSet('GadgetDefinition', 'Json.JsonConfig', 'JsonSchema', 'MassMessageListContent', 'NewsletterContent', 'Scribunto', 'SecurePoll', 'css', 'flow-board', 'javascript', 'json', 'sanitized-css', 'text', 'translate-messagebundle', 'wikitext')]
    [string]$ContentModel = 'wikitext',
    # Unsupported on PCGW: unknown, 

    [Parameter(ValueFromPipelineByPropertyName)]
    [ValidateSet('application/json', 'application/octet-stream', 'application/unknown', 'application/x-binary', 'text/css', 'text/javascript', 'text/plain', 'text/x-wiki')]
    [string]$ContentFormat = 'text/x-wiki',
    # Unsupported on PCGW: unknown/unknown, text/unknown

    # We only allow a subset here since we are just parsing stuff -- not outputting actual pages
    [ValidateSet('', '*', 'Categories', 'EncodedJSConfigVars', 'ExternalLinks', 'HeadHtml', 'Images', 'Indicators', 'IwLinks', 'JSConfigVars', 'LangLinks', 'LimitReportData', 'LimitReportHtml', 'Links', 'Modules', 'ParseTree', 'ParseWarnings', 'Properties', 'Templates', 'Text', 'Wikitext')]
    [string[]]$Properties = @('Text', 'Wikitext', 'Categories', 'Templates', 'Images', 'Links', 'IwLinks', 'ExternalLinks', 'LangLinks', 'Properties', 'ParseWarnings'),
    # Comma-separated list of additional properties to include:
    # categories, categorieshtml, encodedjsconfigvars, externallinks, headhtml, images, indicators, iwlinks, jsconfigvars, langlinks, limitreportdata, limitreporthtml, links, modules, parsetree, parsewarnings, parsewarningshtml, properties, sections, templates, text, wikitext
    # Unsupported on PCGW: ParseWarningsHtml, Subtitle

    # Not supported on PCGW
    #[switch]$MobileFormat,

    [switch]$IncludeLimitReport,

    <#
      Debug
    #>
    [switch]$JSON
  )

  Begin
  {
    $ArrJSON = @()
  }

  Process
  {
    if ($null -eq $script:Config.URI)
    {
      Write-Warning "Not connected to a MediaWiki instance."
      return $null
    }

    $Body = [ordered]@{
      action          = 'parse'
      contentmodel    = $ContentModel
      contentformat   = $ContentFormat
      wrapoutputclass = ''
    }

    if ($Text)
    { $Body.text = $Text }

    if ($Summary)
    {
      $Body.summary = $Summary
      $Body.prop    = ''
    }

    if (-not $IncludeLimitReport)
    { $Body.disablelimitreport = $true }

    # Not supported on PCGW
    #if ($MobileFormat)
    #{ $Body.mobileformat = $true }

    if ($Text -and -not [string]::IsNullOrEmpty($Properties))
    {
      if ($Properties -contains '*')
      { $Properties = @('Categories', 'EncodedJSConfigVars', 'ExternalLinks', 'HeadHtml', 'Images', 'Indicators', 'IwLinks', 'JSConfigVars', 'LangLinks', 'LimitReportData', 'LimitReportHtml', 'Links', 'Modules', 'ParseTree', 'ParseWarnings', 'Properties', 'Templates', 'Text', 'Wikitext') }

      if ($WikiText -and $Properties -notcontains 'wikitext')
      { $Properties += @('wikitext') }
      elseif ($ParsedText -and $Properties -notcontains 'text')
      { $Properties += @('text') }

      $Body.prop = ($Properties.ToLower() -join '|')
    }

    $ArrJSON += Invoke-MWApiRequest -Body $Body -Method POST
  }

  End
  {
    if ($JSON)
    { return $ArrJSON }

    $PSCustomObject = $ArrJSON.parse | ForEach-Object { ConvertFrom-HashtableToPSObject $_ }

    # Irrelevant and confusing, as it points to the "API" page for some random reason
    $PSCustomObject.PSObject.Properties.Remove('Name')
    $PSCustomObject.PSObject.Properties.Remove('ID')

    return $PSCustomObject
  }
}
#endregion

#region Disconnect-MWSession
function Disconnect-MWSession
{
  [CmdletBinding()]
  param (
    <#
      Debug
    #>
    [switch]$JSON
  )

  Begin { }

  Process { }

  End
  {
    if ($null -eq $script:Config.URI)
    { return $null }

    $Body    = [ordered]@{
      action = 'logout'
      token  = (Get-MWCsrfToken) # An edit token is required to sign out...
    }
    
    $Response = Invoke-MWApiRequest -Body $Body -Method POST -IgnoreDisconnect -IgnoreAnonymous -NoAssert

    Clear-MWSession

    if ($JSON)
    { return $Response }

    return $null
  }
}
#endregion

#region Find-MWImage
function Find-MWImage
{
  [CmdletBinding()]
  param
  (
    [ValidateSet('Name', 'Timestamp')]
    [string]$SortProperty = 'Name',

    [Alias('Newer')]
    [switch]$Ascending, # (default)
    [Alias('Older')]
    [switch]$Descending,

    # MediaWiki Default: timestamp|url
    [ValidateSet('', '*', 'BadFile', 'BitDepth', 'CanonicalTitle', 'Comment', 'CommonMetadata', 'Dimensions', 'ExtMetadata', 'MediaType', 'Metadata', 'MIME', 'ParsedComment', 'SHA1', 'Size', 'Timestamp', 'URL', 'User', 'UserID')]
    [string[]]$Properties = @('Timestamp', 'URL'),
    # Timestamp doesn't work?

    [ValidateScript({ Test-MWResultSize -InputObject $PSItem })]
    [string]$ResultSize = 1000,

    [ValidateRange(0, [uint32]::MaxValue)]
    [uint32]$MinSize, # Bytes

    [ValidateRange(0, [uint32]::MaxValue)]
    [uint32]$MaxSize, # Bytes

    [string]$SHA1,
    [string]$SHA1Base36,
    
    <#
      Debug
    #>
    [switch]$JSON
  )

  dynamicparam
  {
    $paramDictionary = [System.Management.Automation.RuntimeDefinedParameterDictionary]::new()

    if ($SortProperty -eq 'Name')
    {
      # [-Name [string]]
      $NameParameterAttribute = [System.Management.Automation.ParameterAttribute]@{
          ParameterSetName    = "BetweenNames"
          Mandatory           = $false
          Position            = 0
      }
      $NameAliasAttribute     = [System.Management.Automation.AliasAttribute]::new('ImageName', 'Prefix')
      $NameCollection         = [System.Collections.ObjectModel.Collection[System.Attribute]]::new()
      $NameCollection.Add($NameParameterAttribute)
      $NameCollection.Add($NameAliasAttribute)
      $NameDynamic            = [System.Management.Automation.RuntimeDefinedParameter]::new(
                           'Name', [string], $NameCollection
      )
      $paramDictionary.Add('Name', $NameDynamic)

      # [-From [string]]
      $FromParameterAttribute = [System.Management.Automation.ParameterAttribute]@{
          ParameterSetName    = "BetweenNames"
          Mandatory           = $false
      }
      $FromCollection         = [System.Collections.ObjectModel.Collection[System.Attribute]]::new()
      $FromCollection.Add($FromParameterAttribute)
      $FromDynamic            = [System.Management.Automation.RuntimeDefinedParameter]::new(
                           'From', [string], $FromCollection
      )
      $paramDictionary.Add('From', $FromDynamic)

      # [-To [string]]
      $ToParameterAttribute   = [System.Management.Automation.ParameterAttribute]@{
          ParameterSetName    = "BetweenNames"
          Mandatory           = $false
      }
      $ToCollection           = [System.Collections.ObjectModel.Collection[System.Attribute]]::new()
      $ToCollection.Add($ToParameterAttribute)
      $ToDynamic              = [System.Management.Automation.RuntimeDefinedParameter]::new(
                           'To', [string], $ToCollection
      )
      $paramDictionary.Add('To', $ToDynamic)
    }

    elseif ($SortProperty -eq 'Timestamp')
    {
      # [-Start [string]]
      $StartParameterAttribute       = [System.Management.Automation.ParameterAttribute]@{
          ParameterSetName           = "BetweenTimestamp"
          Mandatory                  = $false
      }
      $StartParameterAttributeUser   = [System.Management.Automation.ParameterAttribute]@{
          ParameterSetName           = "BetweenTimestampUser"
          Mandatory                  = $false
      }
      $StartParameterAttributeFilter = [System.Management.Automation.ParameterAttribute]@{
          ParameterSetName           = "BetweenTimestampFilter"
          Mandatory                  = $false
      }
      $StartCollection               = [System.Collections.ObjectModel.Collection[System.Attribute]]::new()
      $StartCollection.Add($StartParameterAttribute)
      $StartCollection.Add($StartParameterAttributeUser)
      $StartCollection.Add($StartParameterAttributeFilter)
      $StartDynamic                  = [System.Management.Automation.RuntimeDefinedParameter]::new(
                           'Start', [string], $StartCollection
      )
      $paramDictionary.Add('Start', $StartDynamic)


      # [-End [string]]
      $EndParameterAttribute        = [System.Management.Automation.ParameterAttribute]@{
          ParameterSetName           = "BetweenTimestamp"
          Mandatory                  = $false
      }
      $EndParameterAttributeUser     = [System.Management.Automation.ParameterAttribute]@{
          ParameterSetName           = "BetweenTimestampUser"
          Mandatory                  = $false
      }
      $EndParameterAttributeFilter   = [System.Management.Automation.ParameterAttribute]@{
          ParameterSetName           = "BetweenTimestampFilter"
          Mandatory                  = $false
      }
      $EndCollection                 = [System.Collections.ObjectModel.Collection[System.Attribute]]::new()
      $EndCollection.Add($EndParameterAttribute)
      $EndCollection.Add($EndParameterAttributeUser)
      $EndCollection.Add($EndParameterAttributeFilter)
      $EndDynamic                    = [System.Management.Automation.RuntimeDefinedParameter]::new(
                           'End', [string], $EndCollection
      )
      $paramDictionary.Add('End', $EndDynamic)

      # [-User [string]]
      $UserParameterAttribute        = [System.Management.Automation.ParameterAttribute]@{
          ParameterSetName           = "BetweenTimestampUser"
          Mandatory                  = $true
      }
      $UserCollection                = [System.Collections.ObjectModel.Collection[System.Attribute]]::new()
      $UserCollection.Add($UserParameterAttribute)
      $UserDynamic                   = [System.Management.Automation.RuntimeDefinedParameter]::new(
                           'User', [string], $UserCollection
      )
      $paramDictionary.Add('User', $UserDynamic)

      # [-Filter [string]]
      $FilterParameterAttribute      = [System.Management.Automation.ParameterAttribute]@{
          ParameterSetName           = "BetweenTimestampFilter"
          Mandatory                  = $true
      }
      $FilterValidateSetAttribute    = [System.Management.Automation.ValidateSetAttribute]::new(
                           'All', 'Bots', 'NoBots'
      )
      $FilterCollection              = [System.Collections.ObjectModel.Collection[System.Attribute]]::new()
      $FilterCollection.Add($FilterParameterAttribute)
      $FilterCollection.Add($FilterValidateSetAttribute)
      $FilterDynamic                 = [System.Management.Automation.RuntimeDefinedParameter]::new(
                           'Filter', [string], $FilterCollection
      )
      $paramDictionary.Add('Filter', $FilterDynamic)
    }

    return $paramDictionary
  }

  Begin
  {
    $ArrJSON = @()
  }

  Process
  {
    if ($null -eq $script:Config.URI)
    {
      Write-Warning "Not connected to a MediaWiki instance."
      return $null
    }

    if ($ResultSize -eq 'Unlimited')
    { $ResultSize = [int32]::MaxValue } # int32 because of Select-Object -First [int32]

    # Preparation
    $Body = [ordered]@{
      action        = 'query'
      list          = 'allimages'
      ailimit       = 'max'
      aisort        = $SortProperty.ToLower()
    }

    if (-not [string]::IsNullOrEmpty($Properties))
    {
      if ($Properties -contains '*')
      { $Properties = @('BadFile', 'BitDepth', 'CanonicalTitle', 'Comment', 'CommonMetadata', 'Dimensions', 'ExtMetadata', 'MediaType', 'Metadata', 'MIME', 'ParsedComment', 'SHA1', 'Size', 'Timestamp', 'URL', 'User', 'UserID') }

      $Body.aiprop  = ($Properties.ToLower() -join '|')
    }

    if ($Descending)
    { $Body.aidir = 'descending' } # Older is a synonym for Descending
    elseif ($Ascending)
    { $Body.aidir = 'ascending' } # Newer is a synonym for Ascending

    if ($MinSize)
    { $Body.aiminsize = $MinSize }

    if ($MaxSize)
    { $Body.aimaxsize = $MaxSize }

    # Need to bind dynamic parameters to local variables apparently?

    # BetweenNames
    $Name   = $PSBoundParameters['Name']
    $From   = $PSBoundParameters['From']
    $To     = $PSBoundParameters['To']
    if ($PSBoundParameters.ContainsKey('Name'))
    { $Body.aiprefix = $Name }
    if ($PSBoundParameters.ContainsKey('From'))
    { $Body.aifrom   = $From }
    if ($PSBoundParameters.ContainsKey('To'))
    { $Body.aito     = $To }

    # BetweenTimestamp*
    $Start  = $PSBoundParameters['Start']
    $End    = $PSBoundParameters['End']
    if ($PSBoundParameters.ContainsKey('Start'))
    {
      if ($Start -eq 'now')
      { $Start = (Get-Date) } else {
        $Start = [DateTime]$Start
      }
      $Body.aistart = (Get-Date ($Start).ToUniversalTime() -UFormat '+%Y-%m-%dT%H:%M:%SZ')
    }
    if ($PSBoundParameters.ContainsKey('End'))
    {
      if ($End -eq 'now')
      { $End = (Get-Date) } else {
        $End = [DateTime]$End
      }
      $Body.aiend = (Get-Date ($End).ToUniversalTime() -UFormat '+%Y-%m-%dT%H:%M:%SZ')
    }
    # BetweenTimestampUser / BetweenTimestampFilter
    $User   = $PSBoundParameters['User']
    $Filter = $PSBoundParameters['Filter']
    if ($PSBoundParameters.ContainsKey('User'))
    { $Body.aiuser       = $User }
    if ($PSBoundParameters.ContainsKey('Filter'))
    { $Body.aifilterbots = $Filter.ToLower() }

    $ArrJSON += Invoke-MWApiContinueRequest -Body $Body -Method GET -ResultSize $ResultSize -Node1 'allimages'
  }

  End
  {
    if ($JSON)
    { return $ArrJSON }

    return (($ArrJSON.query.allimages | Select-Object -First $ResultSize) | ForEach-Object { ConvertFrom-HashtableToPSObject $_ })
  }
}
#endregion

#region Find-MWOrphanedRedirect
# Lists orphaned redirect pages which no other pages link to.
function Find-MWOrphanedRedirect
{
  [CmdletBinding()]
  param (
    [ValidateScript({ Test-MWResultSize -InputObject $PSItem })]
    [string]$ResultSize = 1000,
    
    <#
      Debug
    #>
    [switch]$JSON
  )

  Begin {
    $ArrJSON           = @()
    $ArrPSCustomObject = @()
  }

  Process
  {
    if ($ResultSize -eq 'Unlimited')
    { $ResultSize = [int32]::MaxValue }
    # Quite costly operation, so throw the result size warning at the beginning
    else
    { Write-MWWarningResultSize -InputObject $true -DefaultSize 1000 -ResultSize $ResultSize }

    $Pages = Find-MWPage -RedirectOnly -ResultSize Unlimited

    ForEach ($Page in $Pages)
    {
      $Links = Get-MWBackLink -ID $Page.ID
      if ($Links.Count -eq 0)
      {
        $Body = [ordered]@{
          action    = 'query'
          pageids   = $Page.ID
          redirects = $true
        }

        $Response = Invoke-MWApiRequest -Body $Body -Method GET
        $ArrJSON += $Response

        if ($Redirects = $Response.query.redirects)
        {
          $Resolution = $Response.query.pages[0]

          $ObjectProperties = [ordered]@{
            ID           = $Page.ID
            Name         = $Redirects[0].from # Name of the starting page

            # Array of redirect hierarchy
            Redirects    = $Redirects | Select-Object @{
              Name       = 'Target'
              Expression = { $_.to }
            }, @{
              Name       = 'Anchor'
              Expression = { $_.tofragment }
            }

             # Final target of the redirect hierarchy
            Resolved     = [ordered]@{
              Namespace  = (Get-MWNamespace -NamespaceID $Resolution.ns).Name
              Name       = $Resolution.title
              ID         = $Resolution.pageid
            }
          }
          $ArrPSCustomObject += New-Object PSObject -Property $ObjectProperties
        }
      }

      if ($ArrPSCustomObject.Count -ge $ResultSize)
      { break }
    }
  }

  End
  {
    if ($JSON)
    { return $ArrJSON }
   
    return $ArrPSCustomObject
  }
}
#endregion

#region Find-MWPage
# Not to be mistaken for Search-MWPage!
function Find-MWPage
{
  [CmdletBinding(DefaultParameterSetName = 'None')]
  param
  (
    [parameter(ValueFromPipeline, ValueFromPipelineByPropertyName, Position=0)]
    [Alias('PageName', 'Prefix')]
    [string]$Name,

    [Parameter()]
    [ValidateScript({ Test-MWNamespace -InputObject $PSItem })]
    [string]$Namespace, # Only one namespace is supported

    [ValidateScript({ Test-MWResultSize -InputObject $PSItem })]
    [string]$ResultSize = 1000,

    [ValidateRange(0, [uint32]::MaxValue)]
    [uint32]$MinSize, # Bytes

    [ValidateRange(0, [uint32]::MaxValue)]
    [uint32]$MaxSize, # Bytes

    [switch]$Ascending, # default
    [switch]$Descending,

    [switch]$RedirectOnly,
    [switch]$NoRedirect,
    
    [Parameter(ParameterSetName='ByProtection', Mandatory)]
    [ValidateScript({ Test-MWProtectionType -InputObject $PSItem })]
    [string[]]$ProtectionType,

    # ()
    [Parameter(ParameterSetName='ByProtection', Mandatory)]
    [ValidateScript({ Test-MWProtectionLevel -InputObject $PSItem })]
    [string[]]$ProtectionLevel,
    
    <#
      Debug
    #>
    [switch]$JSON
  )

  Begin
  {
    $ArrJSON           = @()
  }

  Process
  {
    if ($null -eq $script:Config.URI)
    {
      Write-Warning "Not connected to a MediaWiki instance."
      return $null
    }

    if ($ResultSize -eq 'Unlimited')
    { $ResultSize = [int32]::MaxValue } # int32 because of Select-Object -First [int32]

    $Body = [ordered]@{
      action        = 'query'
      list          = 'allpages'
      aplimit       = 'max'
    }

    if ($MinSize)
    { $Body.apminsize = $MinSize }

    if ($MaxSize)
    { $Body.apmaxsize = $MaxSize }

    if ($NoRedirects)
    { $Body.apfilterredir = 'nonredirects' }
    elseif ($RedirectOnly)
    { $Body.apfilterredir = 'redirects' }
    else
    { $Body.apfilterredir = 'all' }

    if ($ProtectionType)
    { $Body.apprtype = ($ProtectionType -join '|').ToLower() }

    if ($ProtectionLevel)
    { $Body.apprlevel = ($ProtectionLevel -join '|').ToLower() }

    if ($Descending)
    { $Body.apdir = 'descending' }
    elseif ($Ascending)
    { $Body.apdir = 'ascending' }

    # Use $_Namespace because PowerShell is being really odd at times,
    #   and seemingly executing Test-MWNamespace _after_ we are already within the function...
    $_Namespace = ConvertTo-MWNamespaceID $Namespace -Single

    if ($PSBoundParameters.ContainsKey('Name'))
    {
      if ($Name -like "*:*")
      {
        # if no namespace is specified, but the prefix includes a valid namespace,
        #   we need to convert it or the query will fail with the following error:
        #     [query+allpages][invalidtitle] Bad title "Template:".
        if ([string]::IsNullOrEmpty($_Namespace))
        {
          $PrefixNamespace = (Get-MWNamespace -Name ($Name -split ':')[0])
          if ($null -ne $PrefixNamespace)
          {
            # Move the namespace over to the namespace parameter
            $_Namespace = $PrefixNamespace
            # Remove the namespace from the prefix
            $Name      = $Name.Replace("$($PrefixNamespace.Name):", "")
          }
        }

        # if a namespace is specified, then the prefix may also include the name of a namespace.
        # Because a name such as 'User:Aemony/Template:System requirements' is actually valid.
      }

      if (-not [string]::IsNullOrEmpty($Name))
      { $Body.apprefix = $Name }
    }

    if (-not [string]::IsNullOrEmpty($_Namespace))
    { $Body.apnamespace = $_Namespace }

    $ArrJSON += Invoke-MWApiContinueRequest -Body $Body -Method GET -ResultSize $ResultSize -Node1 'allpages'
  }

  End
  {
    if ($JSON)
    { return $ArrJSON }

    return (($ArrJSON.query.allpages | Select-Object -First $ResultSize) | ForEach-Object { ConvertFrom-HashtableToPSObject $_ })
  }
}
#endregion

#region Find-MWRedirect
function Find-MWRedirect
{
  [CmdletBinding()]
  param (
    [ValidateScript({ Test-MWResultSize -InputObject $PSItem })]
    [string]$ResultSize = 1000,
    
    <#
      Debug
    #>
    [switch]$JSON
  )

  Begin { }

  Process {
    $Parameters = @{
      RedirectOnly = $true
      ResultSize   = $ResultSize
      JSON         = $JSON
    }

    Find-MWPage @Parameters
  }

  End { }
}
#endregion

#region Get-MWBackLink
function Get-MWBackLink
{
  [CmdletBinding(DefaultParameterSetName = 'PageName')]
  param (
    <#
      Core parameters
    #>
    [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName, ParameterSetName = 'PageName', Position=0)]
    [ValidateNotNullOrEmpty()]
    [Alias('Title', 'Identity', 'PageName')]
    [string]$Name,

    [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName, ParameterSetName = 'PageID', Position=0)]
    [Alias('PageID')]
    [int]$ID,

    [ValidateScript({ Test-MWResultSize -InputObject $PSItem })]
    [string]$ResultSize = 1000,
    
    <#
      Debug
    #>
    [switch]$JSON
  )

  Begin
  {
    $ArrJSON = @()
  }

  Process
  {
    if ($null -eq $script:Config.URI)
    {
      Write-Warning "Not connected to a MediaWiki instance."
      return $null
    }

    if ($ResultSize -eq 'Unlimited')
    { $ResultSize = [int32]::MaxValue } # int32 because of Select-Object -First [int32]

    $Body = [ordered]@{
      action  = 'query'
      list    = 'backlinks'
      bllimit = 'max'
    }

    if ($ID)
    { $Body.blpageid = $ID }
    if ($Name)
    { $Body.bltitle = $Name }

    $ArrJSON += Invoke-MWApiContinueRequest -Body $Body -Method GET -ResultSize $ResultSize -Node1 'backlinks'
  }

  End
  {
    if ($JSON)
    { return $ArrJSON }

    return (($ArrJSON.query.backlinks | Select-Object -First $ResultSize) | ForEach-Object { ConvertFrom-HashtableToPSObject $_ })
  }
}
#endregion

#region Get-MWCargoQuery
function Get-MWCargoQuery
{
  param
  (
    [parameter(Mandatory, ValueFromPipelineByPropertyName)]
    [Alias('Tables')]
    [string[]]$Table, # The Cargo database table or tables on which to search

    [parameter(Mandatory, ValueFromPipelineByPropertyName)]
    [Alias('Fields')]
    [string[]]$Field, # The table field(s) to retrieve

    [parameter(ValueFromPipelineByPropertyName)]
    [string]$Where, # The conditions for the query, corresponding to an SQL WHERE clause

    [parameter(ValueFromPipelineByPropertyName)]
    [string]$JoinOn, # Conditions for joining multiple tables, corresponding to an SQL JOIN ON clause

    [parameter(ValueFromPipelineByPropertyName)]
    [string]$GroupBy, # Field(s) on which to group results, corresponding to an SQL GROUP BY clause

    [parameter(ValueFromPipelineByPropertyName)]
    [string]$Having, # Conditions for grouped values, corresponding to an SQL HAVING clause

    [parameter(ValueFromPipelineByPropertyName)]
    [string]$OrderBy, # The order of results, corresponding to an SQL ORDER BY clause

    [parameter(ValueFromPipelineByPropertyName)]
    [uint32]$Offset, # The query offset. The value must be no less than 0.

    [parameter(ValueFromPipelineByPropertyName)]
    [Alias('ResultSize')]
    [uint32]$Limit, # A limit on the number of results returned, corresponding to an SQL LIMIT clause
    
    <#
      Debug
    #>
    [switch]$JSON
  )

  Begin { }

  Process
  {
    if ($null -eq $script:Config.URI)
    {
      Write-Warning "Not connected to a MediaWiki instance."
      return $null
    }
    
    $Body = [ordered]@{
      action = 'cargoquery'
      tables = $Table -join ','
      fields = $Field -join ','
    }

    if ($Field -NotLike "*_pageID*" -and $Field -NotLike "*_pageName*" -and $Field -NotLike "*_pageNamespace*")
    {
      $Body.fields = ($Table[0] + '._pageName=Name,' + $Table[0] + '._pageID=ID,' + $Table[0] + '._pageNamespace=NamespaceID,' + $Body.fields)
      Write-Verbose "_pageID and _pageName was omitted from the Field parameter. They have been added to ensure successful queries:`n$($Body.fields)"
    }

    if ($PSBoundParameters.ContainsKey('Where'))
    { $Body.where = $Where }

    if ($PSBoundParameters.ContainsKey('JoinOn'))
    { $Body.join_on = $JoinOn }

    if ($PSBoundParameters.ContainsKey('GroupBy'))
    { $Body.group_by = $GroupBy }

    if ($PSBoundParameters.ContainsKey('Having'))
    { $Body.having = $Having }

    if ($PSBoundParameters.ContainsKey('OrderBy'))
    { $Body.order_by = $OrderBy }

    if ($PSBoundParameters.ContainsKey('Offset'))
    { $Body.offset = $Offset }

    if ($PSBoundParameters.ContainsKey('Limit'))
    { $Body.limit = $Limit }

    $Response = Invoke-MWApiRequest -Body $Body -Method GET
    
    if ($JSON)
    { return $Response }

    return $Response.cargoquery.title
  }

  End { }
}
#endregion

#region Get-MWCategoryMember
Set-Alias -Name Get-MWGroupMember -Value Get-MWCategoryMember
function Get-MWCategoryMember
{
  [CmdletBinding(DefaultParameterSetName = 'CategoryName')]
  param (
    [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName, ParameterSetName = 'CategoryName', Position=0)]
    [Alias("Category", "Identity", "Group")]
    [string]$Name,

    [parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName, ParameterSetName = 'CategoryID', Position=0)]
    [Alias('CategoryID')]
    [int]$ID,

    [ValidateScript({ Test-MWNamespace -InputObject $PSItem -AllowWildcard })]
    [string[]]$Namespace,

    [ValidateSet('', '*', 'IDs', 'SortKey', 'SortKeyPrefix', 'Timestamp', 'Title', 'Type')]
    [string[]]$Properties = @('IDs', 'Title'),

    [ValidateSet('*', 'Page', 'SubCat', 'File')]
    [string[]]$Type = @('Page', 'SubCat', 'File'),

    [ValidateSet('SortKey', 'Timestamp')]
    [string[]]$SortProperty = 'SortKey',

    [ValidateScript({ Test-MWResultSize -InputObject $PSItem })]
    [string]$ResultSize = 1000,

    [Alias('Newer')]
    [switch]$Ascending, # (default)
    [Alias('Older')]
    [switch]$Descending,
    
    <#
      Debug
    #>
    [switch]$JSON
  )

  dynamicparam
  {
    $paramDictionary = [System.Management.Automation.RuntimeDefinedParameterDictionary]::new()

    if ($SortProperty -eq 'SortKey')
    {
      # Hex Sort Key

      # [-StartSortKey [string]]
      $StartHexSortKeyParameterAttributeName = [System.Management.Automation.ParameterAttribute]@{
          ParameterSetName    = "CategoryName"
          Mandatory           = $false
      }
      $StartHexSortKeyParameterAttributeID = [System.Management.Automation.ParameterAttribute]@{
          ParameterSetName    = "CategoryID"
          Mandatory           = $false
      }
      $StartHexSortKeyCollection         = [System.Collections.ObjectModel.Collection[System.Attribute]]::new()
      $StartHexSortKeyCollection.Add($StartHexSortKeyParameterAttributeName)
      $StartHexSortKeyCollection.Add($StartHexSortKeyParameterAttributeID)
      $StartHexSortKeyDynamic            = [System.Management.Automation.RuntimeDefinedParameter]::new(
                           'StartHexSortKey', [string], $StartHexSortKeyCollection
      )
      $paramDictionary.Add('StartHexSortKey', $StartHexSortKeyDynamic)

      # [-EndSortKey [string]]
      $EndHexSortKeyParameterAttributeName = [System.Management.Automation.ParameterAttribute]@{
          ParameterSetName    = "CategoryName"
          Mandatory           = $false
      }
      $EndHexSortKeyParameterAttributeID = [System.Management.Automation.ParameterAttribute]@{
          ParameterSetName    = "CategoryID"
          Mandatory           = $false
      }
      $EndHexSortKeyCollection         = [System.Collections.ObjectModel.Collection[System.Attribute]]::new()
      $EndHexSortKeyCollection.Add($EndHexSortKeyParameterAttributeName)
      $EndHexSortKeyCollection.Add($EndHexSortKeyParameterAttributeID)
      $EndHexSortKeyDynamic            = [System.Management.Automation.RuntimeDefinedParameter]::new(
                           'EndHexSortKey', [string], $EndHexSortKeyCollection
      )
      $paramDictionary.Add('EndHexSortKey', $EndHexSortKeyDynamic)

      # Prefix Sort Key

      # [-StartSortKeyPrefix [string]]
      $StartSortKeyPrefixParameterAttributeName = [System.Management.Automation.ParameterAttribute]@{
          ParameterSetName    = "CategoryName"
          Mandatory           = $false
      }
      $StartSortKeyPrefixParameterAttributeID = [System.Management.Automation.ParameterAttribute]@{
          ParameterSetName    = "CategoryID"
          Mandatory           = $false
      }
      $StartSortKeyPrefixCollection         = [System.Collections.ObjectModel.Collection[System.Attribute]]::new()
      $StartSortKeyPrefixCollection.Add($StartSortKeyPrefixParameterAttributeName)
      $StartSortKeyPrefixCollection.Add($StartSortKeyPrefixParameterAttributeID)
      $StartSortKeyPrefixDynamic            = [System.Management.Automation.RuntimeDefinedParameter]::new(
                           'StartSortKeyPrefix', [string], $StartSortKeyPrefixCollection
      )
      $paramDictionary.Add('StartSortKeyPrefix', $StartSortKeyPrefixDynamic)

      # [-EndSortKeyPrefix [string]]
      $EndSortKeyPrefixParameterAttributeName = [System.Management.Automation.ParameterAttribute]@{
          ParameterSetName    = "CategoryName"
          Mandatory           = $false
      }
      $EndSortKeyPrefixParameterAttributeID = [System.Management.Automation.ParameterAttribute]@{
          ParameterSetName    = "CategoryID"
          Mandatory           = $false
      }
      $EndSortKeyPrefixCollection         = [System.Collections.ObjectModel.Collection[System.Attribute]]::new()
      $EndSortKeyPrefixCollection.Add($EndSortKeyPrefixParameterAttributeName)
      $EndSortKeyPrefixCollection.Add($EndSortKeyPrefixParameterAttributeID)
      $EndSortKeyPrefixDynamic            = [System.Management.Automation.RuntimeDefinedParameter]::new(
                           'EndSortKeyPrefix', [string], $EndSortKeyPrefixCollection
      )
      $paramDictionary.Add('EndSortKeyPrefix', $EndSortKeyPrefixDynamic)
    }

    if ($SortProperty -eq 'Timestamp')
    {
      # [-Start [string]]
      $StartParameterAttributeName   = [System.Management.Automation.ParameterAttribute]@{
          ParameterSetName           = "CategoryName"
          Mandatory                  = $false
      }
      $StartParameterAttributeID     = [System.Management.Automation.ParameterAttribute]@{
          ParameterSetName           = "CategoryID"
          Mandatory                  = $false
      }
      $StartCollection               = [System.Collections.ObjectModel.Collection[System.Attribute]]::new()
      $StartCollection.Add($StartParameterAttributeName)
      $StartCollection.Add($StartParameterAttributeID)
      $StartDynamic                  = [System.Management.Automation.RuntimeDefinedParameter]::new(
                           'Start', [string], $StartCollection
      )
      $paramDictionary.Add('Start', $StartDynamic)

      # [-End [string]]
      $EndParameterAttributeName     = [System.Management.Automation.ParameterAttribute]@{
          ParameterSetName           = "CategoryName"
          Mandatory                  = $false
      }
      $EndParameterAttributeID       = [System.Management.Automation.ParameterAttribute]@{
          ParameterSetName           = "CategoryID"
          Mandatory                  = $false
      }
      $EndCollection                 = [System.Collections.ObjectModel.Collection[System.Attribute]]::new()
      $EndCollection.Add($EndParameterAttributeName)
      $EndCollection.Add($EndParameterAttributeID)
      $EndDynamic                    = [System.Management.Automation.RuntimeDefinedParameter]::new(
                           'End', [string], $EndCollection
      )
      $paramDictionary.Add('End', $EndDynamic)
    }

    return $paramDictionary
  }

  Begin
  {
    $ArrJSON = @()
  }

  Process
  {
    if ($null -eq $script:Config.URI)
    {
      Write-Warning "Not connected to a MediaWiki instance."
      return $null
    }

    if ($ResultSize -eq 'Unlimited')
    { $ResultSize = [int32]::MaxValue } # int32 because of Select-Object -First [int32]

    if (-not ([string]::IsNullOrEmpty($Name)) -and $Name -notlike "Category:*")
    { $Name = 'Category:' + $Name }

    $Body = [ordered]@{
      action     = 'query'
      list       = 'categorymembers'
      cmlimit    = 'max'
    }

    if ($Name)
    { $Body.cmtitle = $Name }
    else
    { $Body.cmpageid = $ID }

    $_Namespace = ConvertTo-MWNamespaceID $Namespace

    if (-not [string]::IsNullOrEmpty($_Namespace))
    { $Body.cmnamespace = $_Namespace }

    if ($Descending)
    { $Body.cmdir = 'descending' } # Older is a synonym for Descending
    elseif ($Ascending)
    { $Body.cmdir = 'ascending' } # Newer is a synonym for Ascending

    if (-not [string]::IsNullOrEmpty($Properties))
    {
      # Does it include a wildcard?
      if ($Properties -contains '*')
      { $Properties = @('IDs', 'SortKey', 'SortKeyPrefix', 'Timestamp', 'Title', 'Type') }

      # Convert everything to lowercase
      $Properties = $Properties.ToLower()

      $Body.cmprop = ($Properties -join '|')
    }

    if (-not [string]::IsNullOrEmpty($Type))
    {
      # Does it include a wildcard?
      if ($Type -contains '*')
      { $Type = @('Page', 'SubCat', 'File') }

      # Convert everything to lowercase
      $Type = $Type.ToLower()

      $Body.cmtype = ($Type -join '|')
    }

    if (-not [string]::IsNullOrEmpty($SortProperty))
    { $Body.cmsort = $SortProperty.ToLower() }

    # BetweenTimestamp
    $Start = $PSBoundParameters['Start']
    $End   = $PSBoundParameters['End']
    if ($PSBoundParameters.ContainsKey('Start'))
    {
      if ($Start -eq 'now')
      { $Start = (Get-Date) } else {
        $Start = [DateTime]$Start
      }
      $Body.cmstart = (Get-Date ($Start).ToUniversalTime() -UFormat '+%Y-%m-%dT%H:%M:%SZ')
    }
    if ($PSBoundParameters.ContainsKey('End'))
    {
      if ($End -eq 'now')
      { $End = (Get-Date) } else {
        $End = [DateTime]$End
      }
      $Body.cmend = (Get-Date ($End).ToUniversalTime() -UFormat '+%Y-%m-%dT%H:%M:%SZ')
    }

    # Start/End Hex SortKey
    $StartHexSortKey = $PSBoundParameters['StartHexSortKey']
    $EndHexSortKey   = $PSBoundParameters['EndHexSortKey']
    if ($PSBoundParameters.ContainsKey('StartHexSortKey'))
    { $Body.cmstarthexsortkey = $StartHexSortKey }
    if ($PSBoundParameters.ContainsKey('EndHexSortKey'))
    { $Body.cmendhexsortkey = $EndHexSortKey }

    # Start/End Prefix SortKey
    $StartSortKeyPrefix = $PSBoundParameters['StartSortKeyPrefix']
    $EndSortKeyPrefix   = $PSBoundParameters['EndSortKeyPrefix']
    if ($PSBoundParameters.ContainsKey('StartSortKeyPrefix'))
    { $Body.cmstartsortkeyprefix = $StartSortKeyPrefix }
    if ($PSBoundParameters.ContainsKey('EndSortKeyPrefix'))
    { $Body.cmendsortkeyprefix = $EndSortKeyPrefix }
    
    $ArrJSON += Invoke-MWApiContinueRequest -Body $Body -Method GET -ResultSize $ResultSize -Node1 'categorymembers'
  }

  End
  {
    if ($JSON)
    { return $ArrJSON }

    return (($ArrJSON.query.categorymembers | Select-Object -First $ResultSize) | ForEach-Object { ConvertFrom-HashtableToPSObject $_ })
  }
}
#endregion

#region Get-MWCsrfToken
function Get-MWCsrfToken
{
  [CmdletBinding()]
  param (
    [switch]$Force,
    
    <#
      Debug
    #>
    [switch]$JSON
  )

  Begin { }

  Process { }

  End
  {
    if ($null -eq $script:Config.URI)
    {
      Write-Warning "Not connected to a MediaWiki instance."
      return $null
    }

    if ($null -eq $script:CSRFToken -or $Force)
    {
      $Body = [ordered]@{
        action = 'query'
        meta   = 'tokens'
        type   = 'csrf'
      }

      $Response = Invoke-MWApiRequest -Body $Body -Method POST -IgnoreDisconnect -IgnoreAnonymous -NoAssert

      if ($Response.query.tokens.csrftoken)
      { $script:CSRFToken = $Response.query.tokens.csrftoken }

      if ($JSON)
      { return $Response }
    }

    return $script:CSRFToken
  }
}
#endregion

#region Get-MWDuplicateFile
function Get-MWDuplicateFile
{
  [CmdletBinding(DefaultParameterSetName = 'PageName')]
  param (
    <#
      Core parameters
    #>
    [parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName, ParameterSetName = 'PageName', Position=0)]
    [ValidateNotNullOrEmpty()]
    [Alias('Title', 'Identity', 'PageName')]
    [string[]]$Name,

    [parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName, ParameterSetName = 'PageID', Position=0)]
    [Alias('PageID')]
    [int[]]$ID,

    [ValidateScript({ Test-MWResultSize -InputObject $PSItem })]
    [string]$ResultSize = 1000,

    [parameter(ParameterSetName = 'All')]
    [switch]$All,
    
    <#
      Debug
    #>
    [switch]$JSON
  )

  Begin
  {
    $ArrJSON = @()
  }

  Process
  {
    if ($null -eq $script:Config.URI)
    {
      Write-Warning "Not connected to a MediaWiki instance."
      return $null
    }
    
    if ($ResultSize -eq 'Unlimited')
    { $ResultSize = [int32]::MaxValue } # int32 because of Select-Object -First [int32]

    $Body = [ordered]@{}

    # Generator
    if ($All)
    {
      $Body = [ordered]@{
        action    = 'query'
        generator = 'allimages'
        prop      = 'duplicatefiles'
        gailimit  = 'max'
      }
    }
    
    # Regular Query
    else {
      $Body = [ordered]@{
        action  = 'query'
        prop    = 'duplicatefiles'
        dflimit = 'max'
      }
    }

    if ($Name)
    { $Body.titles = $Name -join '|' }

    if ($ID)
    { $Body.pageids = $ID -join '|' }

    $ArrJSON += Invoke-MWApiContinueRequest -Body $Body -Method GET -ResultSize $ResultSize -Node1 'pages'
  }

  End
  {
    if ($JSON)
    { return $ArrJSON }

    $ArrPSCustomObject = @()
    if ($Pages = ($ArrJSON.query.pages | Where-Object { $null -ne $_.duplicatefiles }) )
    {
      ForEach ($Page in $Pages)
      {
        if ($null -eq $Page.duplicatefiles)
        { continue }

        if ($null -ne $Page.missing)
        { Write-Warning "The file '$($Page.title)$($Page.pageid)' does not exist." }

        else
        {
          $ObjectProperties = [ordered]@{
            Namespace  = (Get-MWNamespace -NamespaceID $Page.ns).Name
            Name       = $Page.title
            ID         = $Page.pageid
          }

          if ($Page.duplicatefiles)
          { $ObjectProperties.Duplicates = ($Page.duplicatefiles | ForEach-Object { New-Object -TypeName PSObject -Property $_ }) }

          $ArrPSCustomObject += New-Object PSObject -Property $ObjectProperties
        }
      }
    }
    return $ArrPSCustomObject | Select-Object -First $ResultSize
  }
}
#endregion

#region Get-MWEmbeddedIn
Set-Alias -Name Get-MWTranscludedIn -Value Get-MWEmbeddedIn
function Get-MWEmbeddedIn
{
  [CmdletBinding(DefaultParameterSetName = 'PageName')]
  param (
    <#
      Core parameters
    #>
    [parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName, ParameterSetName = 'PageName', Position=0)]
    [ValidateNotNullOrEmpty()]
    [Alias('Title', 'Identity', 'PageName')]
    [string]$Name,

    [parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName, ParameterSetName = 'PageID', Position=0)]
    [Alias('PageID')]
    [int]$ID,

    [ValidateScript({ Test-MWNamespace -InputObject $PSItem -AllowWildcard })]
    [string[]]$Namespace,

    [switch]$Ascending,            # newer; List oldest first
    [switch]$Descending,           # older; List newest first (default)

    [ValidateSet('All', 'NonRedirects', 'Redirects')]
    [string]$Filter = 'All',

    [ValidateScript({ Test-MWResultSize -InputObject $PSItem })]
    [string]$ResultSize = 1000,
    
    <#
      Debug
    #>
    [switch]$JSON
  )

  Begin
  {
    $ArrJSON = @()
  }

  Process
  {
    if ($null -eq $script:Config.URI)
    {
      Write-Warning "Not connected to a MediaWiki instance."
      return $null
    }
    
    if ($ResultSize -eq 'Unlimited')
    { $ResultSize = [int32]::MaxValue } # int32 because of Select-Object -First [int32]

    $Body = [ordered]@{
      action  = 'query'
      list    = 'embeddedin'
      eilimit = 'max'
    }

    if ($ID)
    { $Body.eipageid = $ID }
    else
    { $Body.eititle = $Name }

    $_Namespace = ConvertTo-MWNamespaceID $Namespace

    if (-not [string]::IsNullOrEmpty($_Namespace))
    { $Body.einamespace = $_Namespace }

    if ($Ascending)
    { $Body.eidir = 'ascending' }
    elseif ($Descending)
    { $Body.eidir = 'descending' }

    $Body.eifilterredir = $Filter.ToLower()

    $ArrJSON += Invoke-MWApiContinueRequest -Body $Body -Method GET -ResultSize $ResultSize -Node1 'embeddedin'
  }

  End
  {
    if ($JSON)
    { return $ArrJSON }

    return (($ArrJSON.query.embeddedin | Select-Object -First $ResultSize) | ForEach-Object { ConvertFrom-HashtableToPSObject $_ })

<#
    $ArrPSCustomObject = @()
    if ($Links = $ArrJSON.query.embeddedin | Select-Object -First $ResultSize)
    {
      ForEach ($Page in $Links)
      {
        $ObjectProperties = [ordered]@{
          Namespace = (Get-MWNamespace -NamespaceID $Page.ns).Name
          Name      = $Page.title
          ID        = $Page.pageid
        }
        $ArrPSCustomObject += New-Object PSObject -Property $ObjectProperties
      }
    }
    return $ArrPSCustomObject
#>
  }
}
#endregion

#region Get-MWImageInfo
function Get-MWImageInfo
{
  [CmdletBinding(DefaultParameterSetName = 'PageName')]
  param (
    <#
      Core parameters
    #>
    [parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName, ParameterSetName = 'PageName', Position=0)]
    [ValidateNotNullOrEmpty()]
    [Alias('Title', 'Identity', 'PageName')]
    [string[]]$Name,

    [parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName, ParameterSetName = 'PageID', Position=0)]
    [Alias('PageID')]
    [int[]]$ID,

    # archivename, badfile, bitdepth, canonicaltitle, comment, commonmetadata, dimensions, extmetadata, mediatype, metadata, mime, parsedcomment, sha1, size, thumbmime, timestamp, uploadwarning, url, user, userid
    [ValidateSet('*', 'ArchiveName', 'BadFile', 'BitDepth', 'CanonicalTitle', 'Comment', 'CommonMetadata', 'Dimensions', 'ExtMetadata', 'MediaType', 'Metadata', 'MIME', 'ParsedComment', 'SHA1', 'Size', 'ThumbMIME', 'Timestamp', 'UploadWarning', 'URL', 'User', 'UserID')]
    [string[]]$Properties = @('Timestamp', 'User'),

    # How many file revisions to return per file.
    [Alias('RevisionLimit')]
    [ValidateScript({ Test-MWResultSize -InputObject $PSItem })]
    [string]$ResultSize = 1,
    
    <#
      Debug
    #>
    [switch]$JSON
  )

  Begin
  {
    $ArrJSON           = @()
  }

  Process
  {
    if ($null -eq $script:Config.URI)
    {
      Write-Warning "Not connected to a MediaWiki instance."
      return $null
    }

    if ($ResultSize -eq 'Unlimited')
    { $ResultSize = [int32]::MaxValue } # int32 because of Select-Object -First [int32]

    $Body     = [ordered]@{
      action  = 'query'
      prop    = 'imageinfo'
    }

    if ($ID)
    { $Body.pageids = $ID -join '|' }
    else
    { $Body.titles = $Name -join '|' }

    $Body.iilimit = $ResultSize

    if (-not [string]::IsNullOrEmpty($Properties))
    {
      # Does it include a wildcard?
      if ($Properties -contains '*')
      { $Properties = @('ArchiveName', 'BadFile', 'BitDepth', 'CanonicalTitle', 'Comment', 'CommonMetadata', 'Dimensions', 'ExtMetadata', 'MediaType', 'Metadata', 'MIME', 'ParsedComment', 'SHA1', 'Size', 'ThumbMIME', 'Timestamp', 'UploadWarning', 'URL', 'User', 'UserID') }
      
      # Convert everything to lowercase
      $Properties = $Properties.ToLower()

      $Body.iiprop = ($Properties -join '|')
    }

    $ArrJSON += Invoke-MWApiContinueRequest -Body $Body -Method GET -ResultSize $ResultSize -Node1 'pages' -Node2 'imageinfo'
  }

  End
  {
    if ($JSON)
    { return $ArrJSON }

    return ($ArrJSON.query.pages | ForEach-Object { ConvertFrom-HashtableToPSObject $_ })
  }
}
#endregion

#region Get-MWImageUsage
function Get-MWImageUsage
{
  [CmdletBinding(DefaultParameterSetName = 'PageName')]
  param (
    <#
      Core parameters
    #>
    [parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName, ParameterSetName = 'PageName', Position=0)]
    [ValidateNotNullOrEmpty()]
    [Alias('Title', 'Identity', 'PageName')]
    [string[]]$Name,

    [parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName, ParameterSetName = 'PageID', Position=0)]
    [Alias('PageID')]
    [int[]]$ID,

    [ValidateScript({ Test-MWNamespace -InputObject $PSItem -AllowWildcard })]
    [string[]]$Namespace,

    [switch]$Ascending,            # newer; List oldest first
    [switch]$Descending,           # older; List newest first (default)

    [ValidateSet('All', 'NonRedirects', 'Redirects')]
    [string]$Filter = 'All',

    [ValidateScript({ Test-MWResultSize -InputObject $PSItem })]
    [string]$ResultSize = 1000,
    
    <#
      Debug
    #>
    [switch]$JSON
  )

  Begin
  {
    $ArrJSON           = @()
  }

  Process
  {
    if ($null -eq $script:Config.URI)
    {
      Write-Warning "Not connected to a MediaWiki instance."
      return $null
    }

    if ($ResultSize -eq 'Unlimited')
    { $ResultSize = [int32]::MaxValue } # int32 because of Select-Object -First [int32]

    $Body     = [ordered]@{
      action  = 'query'
      list    = 'imageusage'
    }

    if ($ID)
    { $Body.iupageid = $ID -join '|' }
    else
    { $Body.iutitle = $Name -join '|' }

    $_Namespace = ConvertTo-MWNamespaceID $Namespace

    if (-not [string]::IsNullOrEmpty($_Namespace))
    { $Body.rcnamespace = $_Namespace }

    if ($Ascending)
    { $Body.eidir = 'ascending' }
    elseif ($Descending)
    { $Body.eidir = 'descending' }

    $Body.iufilterredir = $Filter.ToLower()

    $ArrJSON += Invoke-MWApiContinueRequest -Body $Body -Method GET -ResultSize $ResultSize -Node1 'imageusage'
  }

  End
  {
    if ($JSON)
    { return $ArrJSON }

    return (($ArrJSON.query.imageusage | Select-Object -First $ResultSize) | ForEach-Object { ConvertFrom-HashtableToPSObject $_ })
  }
}
#endregion

#region Get-MWRecentChanges
# https://www.mediawiki.org/wiki/API:RecentChanges
# Very useful for bots!
function Get-MWRecentChanges
{
  [CmdletBinding()]
  param (
    [string[]]$Properties = $null, # Comma-separated list of additional properties to include: comment, flags, ids (default), loginfo, parsedcomment, patrolled, redirect, sha1, sizes, tags, timestamp (default), title (default), user, userid
    [string[]]$Filter     = $null, # Comma-separated list of the critera changes must meet: !anon, !autopatrolled, !bot, !minor, !patrolled, !redirect, anon, autopatrolled, bot, minor, patrolled, redirect, unpatrolled
    [string[]]$Type       = $null, # Comma-separated list of the types of changes to include: categorize, edit, external, log, new
    [ValidateScript({ Test-MWNamespace -InputObject $PSItem -AllowWildcard })]
    [string[]]$Namespace,
    [string]$Start        = $null, # Timestamp to start enumerating from
    [string]$End          = $null, # Timestamp to stop enumerating from
    [switch]$LatestRevision,       # include only the latest revision
    [switch]$Ascending,            # newer; List oldest first
    [switch]$Descending,           # older; List newest first (default)
    [switch]$Patrolled,            # patrolled property, requires elevated permissions
    [string]$User,
    [string]$ExcludeUser,
    [ValidateScript({ Test-MWResultSize -InputObject $PSItem })]
    [string]$ResultSize = 1000,
    
    <#
      Debug
    #>
    [switch]$JSON
  )

  Begin
  {
    $ArrJSON = @()
  }

  Process
  {
    if ($null -eq $script:Config.URI)
    {
      Write-Warning "Not connected to a MediaWiki instance."
      return $null
    }

    if ($ResultSize -eq 'Unlimited')
    { $ResultSize = [int32]::MaxValue } # int32 because of Select-Object -First [int32]

    if (-not [string]::IsNullOrEmpty($Properties))
    {
      # Convert everything to lowercase
      $Properties = $Properties.ToLower()

      # Does it include a wildcard?
      if ($Properties -contains '*')
      { $Properties = @('ids', 'title', 'timestamp', 'user', 'userid', 'redirect', 'loginfo', 'comment', 'parsedcomment', 'sizes', 'flags', 'tags', 'sha1') } # patrolled requires elevated permissions
    }

    # Only applied to Properties right now
    if ($Patrolled)
    {
      if ([string]::IsNullOrEmpty($Properties))
      { $Properties  = @('ids', 'title', 'timestamp', 'patrolled') }
      else
      { $Properties += @('patrolled') }
    }

    if (-not [string]::IsNullOrEmpty($Properties))
    { $Body.rcprop = ($Properties -join '|') }

    if (-not [string]::IsNullOrEmpty($Filter))
    {
      # Convert everything to lowercase
      $Filter = $Filter.ToLower()

      # Does it include a wildcard?
      if ($Filter -contains '*')
      { $Filter = @('anon', 'bot', 'minor', 'redirect') } # patrolled related values requires elevated permissions

      $Body.rcshow = ($Filter -join '|')
    }

    if (-not [string]::IsNullOrEmpty($Type))
    {
      # Convert everything to lowercase
      $Type = $Type.ToLower()

      # Does it include a wildcard?
      if ($Type -contains '*')
      { $Type = @('categorize', 'edit', 'external', 'log', 'new') }

      $Body.rctype = ($Type -join '|')
    }

    $Body = [ordered]@{
      action        = 'query'
      list          = 'recentchanges'
     #rcprop        = 'info'
      rclimit       = 'max'
      rcdir         = 'older'
    }

    if ($PSBoundParameters.ContainsKey('Start'))
    {
      $Body.rcstart = $Start

      Write-Verbose "Using $Start as the start of the enumeration"
    }

    if ($PSBoundParameters.ContainsKey('End'))
    {
      $Body.rcend = $End

      Write-Verbose "Using $End as the end of the enumeration"
    }

    if ($Ascending)
    { $Body.rcdir = 'newer' }
    elseif ($Descending)
    { $Body.rcdir = 'older' }

    if (-not [string]::IsNullOrEmpty($User))
    { $Body.rcuser = $User }

    if (-not [string]::IsNullOrEmpty($ExcludeUser))
    { $Body.rcexcludeuser = $ExcludeUser }

    $_Namespace = ConvertTo-MWNamespaceID $Namespace

    if (-not [string]::IsNullOrEmpty($_Namespace))
    { $Body.rcnamespace = $_Namespace }

    if ($LatestRevision)
    { $Body.rctoponly = $true }

    $ArrJSON += Invoke-MWApiContinueRequest -Body $Body -Method GET -ResultSize $ResultSize -Node1 'recentchanges'
  }

  End {
    if ($JSON)
    { return $ArrJSON }

    $ArrPSCustomObject = @()
    if ($RecentChanges = $ArrJSON.query.recentchanges | Select-Object -First $ResultSize)
    {
      ForEach ($Change in $RecentChanges)
      {
        $ObjectProperties = [ordered]@{
          Type = $Change.type # Always present (type)
        }

        # Timestamp (default; timestamp)
        if ($null -ne $Change.timestamp)
        { $ObjectProperties.Timestamp = $Change.timestamp }

        # Page Name (default; title)
        if ($null -ne $Change.title)
        { $ObjectProperties.Name = $Change.title }

        # Page ID (default; pageid)
        if ($null -ne $Change.pageid)
        { $ObjectProperties.ID = $Change.pageid }

        # Namespace (default; ns)
        if ($null -ne $Change.ns)
        { $ObjectProperties.Namespace = (Get-MWNamespace -NamespaceID $Change.ns).Name }

        # User (user)
        if ($null -ne $Change.user)
        { $ObjectProperties.User = $Change.user }

        # User ID (userid)
        if ($null -ne $Change.userid)
        { $ObjectProperties.UserID = $Change.userid }

        # Bot (bot)
        if ($null -ne $Change.bot)
        { $ObjectProperties.Bot = $true } # Change was done by a bot

        # Redirect (???)
        if ($null -ne $Change.redirect)
        { $ObjectProperties.Redirect = $true } # Change has been redirected/is a redirect

        # Minor (minor)
        if ($null -ne $Change.minor)
        { $ObjectProperties.Minor = $true } # Change is minor

        # Revision ID (default; revid)
        if ($null -ne $Change.revid)
        { $ObjectProperties.RevisionID = $Change.revid }

        # Previous revision ID (default; old_revid)
        if ($null -ne $Change.old_revid)
        { $ObjectProperties.PreviousID = $Change.old_revid }

        # Recent Changes ID (default; rcid)
        if ($null -ne $Change.rcid)
        { $ObjectProperties.RecentChangesID = $Change.rcid }

        # Content-Length (newlen)
        if ($null -ne $Change.newlen)
        { $ObjectProperties.Length = $Change.newlen }

        # Old Content-Length (oldlen)
        if ($null -ne $Change.oldlen)
        { $ObjectProperties.PreviousLength = $Change.oldlen }

        # Comment (comment)
        if ($null -ne $Change.comment)
        { $ObjectProperties.Comment = $Change.comment }

        # Parsed comment (parsedcomment)
        if ($null -ne $Change.parsedcomment)
        { $ObjectProperties.ParsedComment = $Change.parsedcomment }

        # Tags (tags), e.g. 'mw-blank' indicates a blanking change. See Special:Tags for a full list.
        if ($null -ne $Change.tags)
        { $ObjectProperties.Tags = $Change.tags }

        # Flags (???)
        if ($null -ne $Change.flags)
        { $ObjectProperties.Flags = $Change.flags }

        # SHA1 (sha1)
        if ($null -ne $Change.sha1)
        { $ObjectProperties.SHA1 = $Change.sha1 }

        $ArrPSCustomObject += New-Object PSObject -Property $ObjectProperties
      }
    }
    return $ArrPSCustomObject
  }
}
#endregion

#region Get-MWLinks
#TODO: Generator. Evaluate?
function Get-MWLink
{
  [CmdletBinding()]
  param (
    <#
      Core parameters
    #>
    [parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName, ParameterSetName = 'PageName', Position=0)]
    [ValidateNotNullOrEmpty()]
    [Alias('Title', 'Identity', 'PageName')]
    [string[]]$Name,

    [parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName, ParameterSetName = 'PageID', Position=0)]
    [Alias('PageID')]
    [int[]]$ID,

    [ValidateScript({ Test-MWResultSize -InputObject $PSItem })]
    [string]$ResultSize = 1000,
    
    <#
      Debug
    #>
    [switch]$JSON
  )

  Begin
  {
    $ArrJSON = @()
  }

  Process
  {
    if ($null -eq $script:Config.URI)
    {
      Write-Warning "Not connected to a MediaWiki instance."
      return $null
    }

    if ($ResultSize -eq 'Unlimited')
    { $ResultSize = [int32]::MaxValue } # int32 because of Select-Object -First [int32]

    $Body = [ordered]@{
      action    = 'query'
      generator = 'links'
      prop      = 'info'
      gpllimit  = 'max'
    }

    if ($ID)
    { $Body.pageids = $ID -join '|' }
    else
    { $Body.titles = $Name -join '|' }

    $ArrJSON += Invoke-MWApiContinueRequest -Body $Body -Method GET -ResultSize $ResultSize -Node1 'pages'
  }

  End
  {
    if ($JSON)
    { return $ArrJSON }

    $ArrPSCustomObject = @()
    if ($Pages = $ArrJSON.query.pages | Select-Object -First $ResultSize)
    {
      ForEach ($Page in $Pages)
      {
        $ObjectProperties = [ordered]@{
          Namespace = (Get-MWNamespace -NamespaceID $Page.ns).Name
          Name      = $Page.title
          ID        = $Page.pageid
          Redirect  = ($null -ne $Page.redirect)
          Missing   = ($null -ne $Page.redirect)
        }
        $ArrPSCustomObject += New-Object PSObject -Property $ObjectProperties
      }
    }
    return $ArrPSCustomObject
  }
}
#endregion

#region Get-MWNamespace
function Get-MWNamespace
{
  [CmdletBinding(DefaultParameterSetName = 'All')]
  param (
    <#
      Core parameters
    #>
    [Parameter(Mandatory, ValueFromPipelineByPropertyName, ParameterSetName = 'NamespaceName', Position=0)]
    [AllowEmptyString()] # Main namespace has no name
    [Alias('Title', 'Identity', 'Name')]
    [string]$NamespaceName,

    [Parameter(Mandatory, ValueFromPipelineByPropertyName, ParameterSetName = 'NamespaceID', Position=0)]
    [ValidateNotNullOrEmpty()]
    [Alias('ID')]
    [int32]$NamespaceID, # int32 cuz namespace IDs can be negative

    [Parameter(ParameterSetName = 'All')]
    [switch]$All,

    # Negative namespaces (Media and Special) are special and seldom used/supported through the API.
    [switch]$IncludeNegative,
    
    <#
      Debug
    #>
    [switch]$JSON
  )

  Begin { }

  Process
  {
    if ($null -eq $script:Config.URI)
    {
      Write-Warning "Not connected to a MediaWiki instance."
      return $null
    }

    $NamespaceName = $NamespaceName.Replace(':', '')

    if ($null -ne $script:Cache.Namespace)
    {
      $LocalCopy = $null

      if ($IncludeNegative)
      { $LocalCopy = $script:Cache.Namespace }
      else 
      { $LocalCopy = $script:Cache.Namespace | Where-Object ID -ge 0 }

          if ($PSBoundParameters.ContainsKey('NamespaceName'))
      { return ($LocalCopy | Where-Object Name -EQ $NamespaceName | Copy-Object) }
      elseif ($PSBoundParameters.ContainsKey('NamespaceID'))
      { return ($LocalCopy | Where-Object ID   -EQ $NamespaceID   | Copy-Object) }
      else
      { return ($LocalCopy                                        | Copy-Object) }
    }

    return $null
  }

  End { }
}
#endregion

#region Get-MWNamespacePage
function Get-MWNamespacePage
{
  [CmdletBinding()]
  param
  (
    [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName, Position=0)]
    [string]$Name,

    [ValidateScript({ Test-MWResultSize -InputObject $PSItem })]
    [string]$ResultSize = 1000,

    [switch]$JSON
  )

  Begin {
    if ($ResultSize -eq 'Unlimited')
    { $ResultSize = [int32]::MaxValue } # int32 because of Select-Object -First [int32]
  }

  Process {
    $Parameters  = @{
      Namespace  = $Name
      ResultSize = $ResultSize
      JSON       = $JSON
    }

    Find-MWPage @Parameters
  }

  End { }
}
#endregion

#region Get-MWPage
function Get-MWPage
{
  [CmdletBinding(DefaultParameterSetName = 'PageName')]
  param (
    <#
      Core parameters
    #>
    [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName, ParameterSetName = 'PageName', Position=0)]
    [ValidateNotNullOrEmpty()]
    [Alias('Title', 'Identity', 'PageName')]
    [string]$Name,

    [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName, ParameterSetName = 'PageID', Position=0)]
    [Alias('PageID')]
    [int]$ID,

    # MediaWiki Default: text|langlinks|categories|links|templates|images|externallinks|sections|revid|displaytitle|iwlinks|properties|parsewarnings
    [ValidateSet('', '*', 'Categories', 'CategoriesHtml', 'DisplayTitle', 'EncodedJSConfigVars', 'ExternalLinks', 'HeadHtml', 'Images', 'Indicators', 'IwLinks', 'JSConfigVars', 'LangLinks', 'LimitReportData', 'LimitReportHtml', 'Links', 'Modules', 'ParseTree', 'ParseWarnings', 'Properties', 'RevId', 'Sections', 'Templates', 'Text', 'Wikitext')]
    [string[]]$Properties = @('RevID', 'DisplayTitle', 'Categories', 'Templates', 'Images', 'ExternalLinks', 'Sections'),
    # Comma-separated list of additional properties to include:
    # categories, categorieshtml, displaytitle, encodedjsconfigvars, externallinks, headhtml, images, indicators, iwlinks, jsconfigvars, langlinks, limitreportdata, limitreporthtml, links, modules, parsetree, parsewarnings, parsewarningshtml, properties, revid, sections, subtitle, templates, text, wikitext
    # Deprecated: headitems
    # Unsupported on PCGW: ParseWarningsHtml, Subtitle

    [switch]$ParsedText,
    [switch]$WikiText,

    [switch]$FollowRedirects,

    [Alias('Additional', 'Extended')]
    [switch]$Information, # Switch to enable a subcall to Get-MWPageInfo

    <#
      Debug
    #>
    [switch]$JSON
  )

  Begin
  {
    $ArrJSON = @()
  }

  Process
  {
    if ($null -eq $script:Config.URI)
    {
      Write-Warning "Not connected to a MediaWiki instance."
      return $null
    }

    $Body = [ordered]@{
      action = 'parse'
    }

    if ($ID)
    { $Body.pageid = $ID }
    elseif ($Name)
    { $Body.page = $Name }

    if (-not [string]::IsNullOrEmpty($Properties))
    {
      if ($Properties -contains '*')
      { $Properties = @('Categories', 'CategoriesHtml', 'DisplayTitle', 'EncodedJSConfigVars', 'ExternalLinks', 'HeadHtml', 'Images', 'Indicators', 'IwLinks', 'JSConfigVars', 'LangLinks', 'LimitReportData', 'LimitReportHtml', 'Links', 'Modules', 'ParseTree', 'ParseWarnings', 'Properties', 'RevId', 'Sections', 'Templates', 'Text', 'Wikitext') }

      if ($WikiText -and $Properties -notcontains 'wikitext')
      { $Properties += @('wikitext') }
      elseif ($ParsedText -and $Properties -notcontains 'text')
      { $Properties += @('text') }

      $Body.prop = ($Properties.ToLower() -join '|')
    }

    if ($FollowRedirects)
    { $Body.redirects = $null }

    $ArrJSON += Invoke-MWApiRequest -Body $Body -Method POST
  }

  End
  {
    if ($JSON)
    { return $ArrJSON }

    $PSCustomObject = $ArrJSON.parse | ForEach-Object { ConvertFrom-HashtableToPSObject $_ }

    if ($Information)
    {
      $Extended = Get-MWPageInfo -ID $PSCustomObject.ID
      foreach ($Property in ($Extended | Get-Member -MemberType Properties | Select-Object -ExpandProperty Name))
      {
        $Value = $Extended.$Property
        
        # LastRevisionID == RevisionID
        if ($Property -eq 'LastRevisionID')
        {
          if ($PSCustomObject.PSObject.Properties.Name -contains 'RevisionID')
          { continue }
          else
          { $Property = 'RevisionID' }
        }

        $PSCustomObject | Add-Member -MemberType NoteProperty -Name $Property -Value $Value -Force
      }
    }

    return $PSCustomObject
  }
}
#endregion

#region Get-MWPageInfo
function Get-MWPageInfo
{
  [CmdletBinding(DefaultParameterSetName = 'PageName')]
  param (
    <#
      Core parameters
    #>
    [parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName, ParameterSetName = 'PageName', Position=0)]
    [ValidateNotNullOrEmpty()]
    [Alias('Title', 'Identity', 'PageName')]
    [string[]]$Name,

    [parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName, ParameterSetName = 'PageID', Position=0)]
    [Alias('PageID')]
    [int[]]$ID,

    [switch]$FollowRedirects,
    
    <#
      Debug
    #>
    [switch]$JSON
  )

  Begin
  {
    $ArrJSON = @()
  }

  Process
  {
    if ($null -eq $script:Config.URI)
    {
      Write-Warning "Not connected to a MediaWiki instance."
      return $null
    }

    $Body = [ordered]@{
      action = 'query'
      prop   = 'info'
    }

    if ($Name)
    { $Body.titles = $Name -join '|' }

    if ($ID)
    { $Body.pageids = $ID -join '|' }

    if ($FollowRedirects)
    { $Body.redirects = $null }

    $Response = Invoke-MWApiRequest -Body $Body -Method GET
    $ArrJSON += $Response
  }

  End
  {
    if ($JSON)
    { return $ArrJSON }
    
    return $ArrJSON.query.pages | ForEach-Object { ConvertFrom-HashtableToPSObject $_ }
  }
}
#endregion

#region Get-MWProtectionLevel
Set-Alias -Name Get-MWRestrictionLevel -Value Get-MWProtectionLevel
function Get-MWProtectionLevel
{
  return $script:Cache.RestrictionLevel
}
#endregion

#region Get-MWProtectionType
Set-Alias -Name Get-MWRestrictionType -Value Get-MWProtectionType
function Get-MWProtectionType
{
  return $script:Cache.RestrictionType
}
#endregion

#region Get-MWSession
function Get-MWSession
{
  [CmdletBinding()]
  param
  (
    # Used by Invoke-MWApiRequest to suppress anonymous warnings
    [switch]$IgnoreAnonymous
  )

  Begin { }

  Process
  {
    if ($null -eq $global:MWSession)
    { Write-Verbose "There is no active MediaWiki session! Please use Connect-MWSession to sign in to a MediaWiki API endpoint." }
    <#
    elseif ($script:MWSessionGuest -eq $true -and $IgnoreAnonymous -eq $false)
    { Write-Warning "Using an anonymous guest session; some features and functionality may be unavailable." }
    #>

    return $global:MWSession
  }

  End { }
}
#endregion

#region Get-MWSiteInfo
function Get-MWSiteInfo
{
  [CmdletBinding()]
  param
  (
    # Default: general
    [Parameter(Position=0)]
    [ValidateSet('', '*', 'dbrepllag', 'defaultoptions', 'extensions', 'extensiontags', 'fileextensions', 'functionhooks', 'general', 'interwikimap', 'languages', 'languagevariants', 'libraries', 'magicwords', 'namespacealiases', 'namespaces', 'protocols', 'restrictions', 'rightsinfo', 'showhooks', 'skins', 'specialpagealiases', 'statistics', 'uploaddialog', 'usergroups', 'variables')]
    [string[]]$Properties = @('general', 'namespaces', 'restrictions'),
    # Comma-separated list of additional properties to include:
    # autocreatetempuser, autopromote, autopromoteonce, clientlibraries, copyuploaddomains, dbrepllag, defaultoptions, extensions, extensiontags, fileextensions, functionhooks, general, interwikimap, languages, languagevariants, libraries, magicwords, namespacealiases, namespaces, protocols, restrictions, rightsinfo, showhooks, skins, specialpagealiases, statistics, uploaddialog, usergroups, variables
    # Not supported on PCGW? autocreatetempuser, autopromote, autopromoteonce, clientlibraries, copyuploaddomains
    
    <#
      Debug
    #>
    [switch]$JSON
  )

  Begin { }

  Process { }

  End
  {
    if ($null -eq $script:Config.URI)
    {
      Write-Warning "Not connected to a MediaWiki instance."
      return $null
    }

    if ($Properties -contains '*')
    { $Properties = @('dbrepllag', 'defaultoptions', 'extensions', 'extensiontags', 'fileextensions', 'functionhooks', 'general', 'interwikimap', 'languages', 'languagevariants', 'libraries', 'magicwords', 'namespacealiases', 'namespaces', 'protocols', 'restrictions', 'rightsinfo', 'showhooks', 'skins', 'specialpagealiases', 'statistics', 'uploaddialog', 'usergroups', 'variables') }

    $Body = [ordered]@{
      action = 'query'
      meta   = 'siteinfo'
      siprop = ($Properties.ToLower() -join '|')
    }

    $Response = Invoke-MWApiRequest -Body $Body -Method GET -IgnoreDisconnect -IgnoreAnonymous

    # TODO: Translate to PSCustomObject

    # Update the local caches if we can retrieve stuff
    $Output = $null
    if ($Output = $Response.query)
    {
      if ($null -ne $Response.query.restrictions)
      {
        $script:Cache.RestrictionType  = $Response.query.restrictions.types
        $script:Cache.RestrictionLevel = $Response.query.restrictions.levels | Where-Object { $PSItem -ne '' }
      }

      # Update the local namespace cache
      if ($Namespaces = ConvertFrom-HashtableToPSObject $Response.query.namespaces)
      {
        $ArrNamespaces = @()
        ForEach ($NamespaceProperty in $Namespaces.PsObject.Properties)
        {
          $Namespace      = $NamespaceProperty.Value
          $Namespace      = Rename-PropertyName $Namespace -PropertyName 'Content' -NewPropertyName 'IsContentNamespace'
          $ArrNamespaces += $Namespace
        }

        # Populate the namespaces of MediaWiki to a local variable
        $script:Cache.Namespace = $ArrNamespaces
      }
    }

    # Return raw JSON if requested
    if ($JSON)
    { return $Response }

    # Return a PSCustomObject
    return ConvertFrom-HashtableToPSObject $Output
  }
}
#endregion

#region Get-MWTranscludedIn
<#
function Get-MWTranscludedIn
{
  [CmdletBinding()]
  param (
    [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
    [Alias('Title', 'Identity', 'PageName')]
    [string[]]$Name,

    [ValidateScript({ Test-MWNamespace -InputObject $PSItem -AllowWildcard })]
    [string[]]$Namespace,

    [ValidateSet('', '*', 'PageID', 'Title', 'Redirect')]
    [string[]]$Properties = @('PageID', 'Title', 'Redirect'),

    [ValidateScript({ Test-MWResultSize -InputObject $PSItem })]
    [string]$ResultSize = 1000,
    
    [switch]$JSON
  )

  Begin
  {
    $ArrJSON = @()
  }

  Process
  {
    if ($null -eq $script:Config.URI)
    {
      Write-Warning "Not connected to a MediaWiki instance."
      return $null
    }

    if ($ResultSize -eq 'Unlimited')
    { $ResultSize = [int32]::MaxValue }
    # Quite costly operation, so throw the result size warning at the beginning
    else
    { Write-MWWarningResultSize -InputObject $true -DefaultSize 1000 -ResultSize $ResultSize }

    $Body = [ordered]@{
      action  = 'query'
      prop    = 'transcludedin'
      titles  = $Name -join '|'
      tilimit = 'max'
    }

    if (-not [string]::IsNullOrEmpty($Properties))
    {
      # Convert everything to lowercase
      $Properties = $Properties.ToLower()

      # Does it include a wildcard?
      if ($Properties -contains '*')
      { $Properties = @('pageid', 'title', 'redirect') }

      $Body.tiprop = ($Properties -join '|')
    }

    $_Namespace = ConvertTo-MWNamespaceID $Namespace

    if (-not [string]::IsNullOrEmpty($_Namespace))
    { $Body.tinamespace = $_Namespace }
    
    $ArrJSON += Invoke-MWApiContinueRequest -Body $Body -Method GET -ResultSize ([int32]::MaxValue) -Node1 'pages' -Node2 'transcludedin'
  }

  End
  {
    if ($JSON)
    { return $ArrJSON }

    # Cannot use ConvertFrom-HashtableToPSObject due to the complexity, so let's do it manually
    $ArrPSCustomObject = @()

    # Select all unique pages
    if ($Pages = ($ArrJSON.query.pages.title | Select-Object -Unique))
    {
      # Go through each unique page
      ForEach ($Page in $Pages)
      {
        $TempArray = @() # This holds the subject pages that the object page is transcluded in.

        # Extract all 
        $Items = ($ArrJSON.query.pages | Where-Object title -eq $Page)
        ForEach ($TranscludedPage in ($Items.transcludedin | Select-Object -First $ResultSize))
        {
          $ObjectProperties = [ordered]@{
            Namespace       = (Get-MWNamespace -NamespaceID $TranscludedPage.ns).Name
            Name            = $TranscludedPage.title
            ID              = $TranscludedPage.pageid
          }
          $TempArray += New-Object PSObject -Property $ObjectProperties
        }

        # All Items are technically identical beyond their .transcludedin value.
        # So let us just use the first item of the array to fetch the namespace/title/pageid of the root page
        $ObjectProperties = [ordered]@{
          Namespace       = (Get-MWNamespace -NamespaceID $Items[0].ns).Name
          Name            = $Items[0].title
          ID              = $Items[0].pageid
          TranscludedIn   = $TempArray
        }
        $ArrPSCustomObject += New-Object PSObject -Property $ObjectProperties
      }
    }

    return $ArrPSCustomObject
  }
}
#>
#endregion

#region Get-MWUserInfo
function Get-MWUserInfo
{
  [CmdletBinding()]
  param
  (
    # Use * to include all properties
    [Parameter(Position=0)]
    [ValidateSet('', '*', 'blockinfo', 'centralids', 'changeablegroups', 'editcount', 'email', 'groupmemberships', 'groups', 'hasmsg', 'implicitgroups', 'latestcontrib', 'options', 'ratelimits', 'realname', 'registrationdate', 'rights', 'unreadcount')]
    [string[]]$Properties = @('groups', 'rights', 'ratelimits', 'latestcontrib', 'hasmsg', 'unreadcount', 'editcount'),
    # Comma-separated list of additional properties to include:
    # cancreateaccount, blockinfo, centralids, changeablegroups, editcount, email, groupmemberships, groups, hasmsg, implicitgroups, latestcontrib, options, ratelimits, realname, registrationdate, rights, theoreticalratelimits, unreadcount
    # Not supported on PCGW? cancreateaccount, theoreticalratelimits, 
    
    <#
      Debug
    #>
    [switch]$JSON
  )

  Begin { }

  Process { }

  End
  {
    if ($null -eq $script:Config.URI)
    {
      Write-Warning "Not connected to a MediaWiki instance."
      return $null
    }

    if ($Properties -contains '*')
    { $Properties = @('blockinfo', 'centralids', 'changeablegroups', 'editcount', 'email', 'groupmemberships', 'groups', 'hasmsg', 'implicitgroups', 'latestcontrib', 'options', 'ratelimits', 'realname', 'registrationdate', 'rights', 'unreadcount') }

    $Body = [ordered]@{
      action = 'query'
      meta   = 'userinfo'
      uiprop = ($Properties.ToLower() -join '|')
    }

    $Response = Invoke-MWApiRequest -Body $Body -Method GET -IgnoreDisconnect -IgnoreAnonymous

    # TODO: Translate to PSCustomObject

    if ($JSON)
    { return $Response }

    $ArrPSCustomObject = $null
    if ($UserInfo = $Response.query.userinfo)
    {
      $ObjectProperties = [ordered]@{
        ID        = $UserInfo.id
        Name      = $UserInfo.name
      }

      if ($null -ne $UserInfo.anon)
      { $ObjectProperties.Anonymous = $true }

      if ($null -ne $UserInfo.blockinfo)
      { $ObjectProperties.BlockInfo = $UserInfo.blockinfo}

      if ($null -ne $UserInfo.messages)
      { $ObjectProperties.Messages = $UserInfo.messages }

      if ($null -ne $UserInfo.unreadcount)
      { $ObjectProperties.UnreadCount = $UserInfo.unreadcount }

      # Adds the date of user's latest contribution.
      if ($null -ne $UserInfo.latestcontrib)
      { $ObjectProperties.LatestContribution = $UserInfo.latestcontrib }

      if ($null -ne $UserInfo.rights)
      { $ObjectProperties.Rights = $UserInfo.rights }

      if ($null -ne $UserInfo.ratelimits)
      { $ObjectProperties.RateLimits = $UserInfo.ratelimits }

      if ($null -ne $UserInfo.theoreticalratelimits)
      { $ObjectProperties.TheoreticalRateLimits = $UserInfo.theoreticalratelimits }

      if ($null -ne $UserInfo.groups)
      { $ObjectProperties.Groups = $UserInfo.groups }

      if ($null -ne $UserInfo.groupmemberships)
      { $ObjectProperties.GroupMemberships = $UserInfo.groupmemberships }

      if ($null -ne $UserInfo.implicitgroups)
      { $ObjectProperties.ImplicitGroups = $UserInfo.implicitgroups }

      # Lists the groups the current user can add to and remove from.
      if ($null -ne $UserInfo.changeablegroups)
      { $ObjectProperties.ChangeableGroups = $UserInfo.changeablegroups }

      if ($null -ne $UserInfo.options)
      { $ObjectProperties.Options = $UserInfo.options }

      if ($null -ne $UserInfo.preferencestoken)
      { $ObjectProperties.PreferencesToken = $UserInfo.preferencestoken }

      if ($null -ne $UserInfo.editcount)
      { $ObjectProperties.EditCount = $UserInfo.editcount }

      if ($null -ne $UserInfo.realname)
      { $ObjectProperties.RealName = $UserInfo.realname }

      if ($null -ne $UserInfo.email)
      { $ObjectProperties.Email = $UserInfo.email }

      if ($null -ne $UserInfo.emailauthenticated)
      { $ObjectProperties.EmailAuthenticated = $UserInfo.emailauthenticated }

      if ($null -ne $UserInfo.registrationdate)
      { $ObjectProperties.RegistrationDate = $UserInfo.registrationdate }

      if ($null -ne $UserInfo.cancreateaccount)
      { $ObjectProperties.CanCreateAccount = $true }

      # Adds the central IDs and attachment status for the user.
      if ($null -ne $UserInfo.centralids)
      { $ObjectProperties.CentralIDs = $UserInfo.centralids }

      # Adds the central IDs and attachment status for the user.
      if ($null -ne $UserInfo.attachedlocal)
      { $ObjectProperties.AttachedLocal = $UserInfo.attachedlocal }

      # Echoes the Accept-Language header sent by the client in a structured format.
      if ($null -ne $UserInfo.acceptlang)
      { $ObjectProperties.AcceptLanguage = $UserInfo.acceptlang }

      $ArrPSCustomObject = New-Object PSObject -Property $ObjectProperties
    }
    return $ArrPSCustomObject
  }
}
#endregion

#region Invoke-MWApiContinueRequest
# Helper function to loop over and retrieve all available results
function Invoke-MWApiContinueRequest
{
  [CmdletBinding()]
  param (
    [Parameter(Mandatory)]
    $Body,

    [ValidateSet('GET', 'POST')]
    $Method,

    [int32]$ResultSize = 0,

    # We assume, perhaps naively, that all continue requests always use a path like
    # .query.$Node1 for the queried results...
    [string]$Node1 = 'pages',

    # And evidently we were wrong... :O
    [string]$Node2 = '',

    $Uri = ($script:Config.URI)
  )

  Begin
  {
    $ArrJSON = @()
  }

  Process 
  {
    $Request = $Body

    do
    {
      $Response = Invoke-MWApiRequest -Body $Request -Method $Method
      $ArrJSON += $Response

      # Break when we have hit the desired amount
      if ($ResultSize -gt 0)
      {
        if ($Node2 -eq '')
        {
          if ($ArrJSON.query.$Node1.Count -ge $ResultSize)
          {
            $MoreAvailable = ($Response.('continue') -or $ArrJSON.query.$Node1.Count -ge $ResultSize)
            Write-MWWarningResultSize -InputObject $MoreAvailable -DefaultSize 1000 -ResultSize $ResultSize
            break
          }
        } else {
          if ($ArrJSON.query.$Node1.$Node2.Count -ge $ResultSize)
          {
            $MoreAvailable = ($Response.('continue') -or $ArrJSON.query.$Node1.$Node2.Count -ge $ResultSize)
            Write-MWWarningResultSize -InputObject $MoreAvailable -DefaultSize 1000 -ResultSize $ResultSize
            break
          }
        }
      }

      #$Response | ConvertTo-Json -Depth 10 | Out-File '.\json.json' -Append

      # Continue can sometimes include another element (e.g. dfcontinue instead of gaicontinue)
      # so we need to reset the request and carry the whole continue array over...
      $Request = $Body

      if ($null -ne $Response.('continue'))
      {
        # Some continue values, e.g. offsets, might already be present in the original
        # so we need to remove any of those from the object first...
        ForEach ($Object in $Response.('continue').GetEnumerator())
        { $Request.Remove($Object.Name) }

        # Add the new continue values over
        $Request += $Response.('continue')
      }
    } while ($null -ne $Response.('continue'))
  }

  End
  {
    return $ArrJSON
  }
}

#endregion

#region Invoke-MWApiRequest
function Invoke-MWApiRequest
{
  [CmdletBinding(DefaultParameterSetName = 'WebSession')]
  param (
    [Parameter(Mandatory, Position=0)]
    $Body,

    [ValidateSet('GET', 'POST')]
    [Parameter(Mandatory, Position=1)]
    $Method,

    [Parameter()]
    $Uri = ($script:Config.URI),

    # In seconds
    [Parameter()]
    [int32]$RateLimit = 60,

    # Used by pretty much all cmdlets
    [Parameter(ParameterSetName = 'WebSession')]
    [Microsoft.PowerShell.Commands.WebRequestSession]
    $WebSession,

    # Used by Connect-MWSession
    [Parameter(ParameterSetName = 'SessionVariable')]
    [string]
    $SessionVariable,

    # Used by Disconnect-MWSession and Get-MWCsrfToken to not renew expired CSRF/edit tokens
    [switch]$IgnoreDisconnect,
    # Used by Disconnect-MWSession and Get-MWCsrfToken and Get-MWUserInfo to suppress anonymous warnings
    [switch]$IgnoreAnonymous,
    # Used by Disconnect-MWSession and Get-MWCsrfToken and Connect-MWSession to suppress adding asserings to the calls
    [switch]$NoAssert
  )

  Begin { }

  Process
  {
    # Enforce JSON v2, with plain text error formatting
    $Body          += @{
      format        = 'json'
      formatversion = '2'
      errorformat   = 'plaintext'
      curtimestamp  = $true # omit outright to disable
    }

    if ($NoAssert -eq $false)
    {
      # Assert: Anon
      if ($script:MWSessionGuest)
      { $Body.assert      = 'anon' }

      # Assert: Bot
      elseif ($script:MWSessionBot)
      {
        $Body.assert      = 'bot'
        $Body.assertuser  = $script:Cache.UserInfo.Name
      }
      
      # Assert: Username
      elseif ($script:Cache.UserInfo.Name)
      {
        $Body.assert      = 'user'
        $Body.assertuser  = $script:Cache.UserInfo.Name
      }
    }

    $Attempt    = 0 # Max three attempts before aborting
    $JsonObject = $null
    $Retry      = $false

    do {
      # Reset every loop
      $Retry         = $false

      # If we have signed out/in again, we need to renew the edit token as it has expired
      if ($null -ne $Body.token -and $Body.token -ne (Get-MWCsrfToken))
      { $Body.token = (Get-MWCsrfToken) }

      $RequestParams = @{
        Body         = $Body
        Uri          = $Uri
        Method       = $Method
      }

      if ($PSBoundParameters.ContainsKey('SessionVariable'))
      {
        $RequestParams   += @{
          SessionVariable = $SessionVariable
        }
      } elseif ($WebSession) {
        $RequestParams   += @{
          WebSession      = $WebSession
        }
      } else {
        $RequestParams   += @{
          WebSession      = if ($IgnoreAnonymous) { (Get-MWSession -IgnoreAnonymous) } else { Get-MWSession }
        }
      }

      Write-Debug ($RequestParams | ConvertTo-Json -Depth 10)
      $Response = Invoke-WebRequest @RequestParams

      # Built-in : ConvertFrom-Json
      # Custom   : ConvertFrom-JsonToHashtable
      if ($JsonObject = ConvertFrom-JsonToHashtable $Response.Content)
      {
        $Messages     = @()
        $RateLimited  = $false
        $Disconnected = $false

        # Errors
        if ($null -ne $JsonObject.errors)
        {
          $JsonObject.errors | ConvertTo-Json -Depth 100 | Out-File 'errors.json'

          ForEach ($item in $JsonObject.errors)
          {
            $message = @{
              Type   = 'Error'
              Code   = $item.code
              Text   = $item.text
              Module = $item.module
            }
            $Messages += $message
          }
        }

        # Warnings
        if ($null -ne $JsonObject.warnings)
        {
          $JsonObject.warnings | ConvertTo-Json -Depth 100 | Out-File 'warnings.json'

          ForEach ($item in $JsonObject.warnings)
          {
            $message = @{
              Type   = 'Warning'
              Code   = $item.code
              Text   = $item.text
              Module = $item.module
            }
            $Messages += $message
          }
        }

        # Print all messages
        ForEach ($Message in $Messages)
        {
          if ($Message.Type -eq 'Error')
          {
            [Console]::BackgroundColor = 'Black'
            [Console]::ForegroundColor = 'Red'
            [Console]::Error.WriteLine("[$($Message.Module)][$($Message.Code)] $($Message.Text)")
            [Console]::ResetColor()
          }

          else #if ($Message.Type -eq 'Warning')
          { Write-Warning "[$($Message.Module)][$($Message.Code)] $($Message.Text)" }
        }

        $RateLimited  = ($Messages.Code -contains 'ratelimited')
        $Disconnected = (
          $Messages.Code -contains 'badtoken'         -or
          $Messages.Code -contains 'assertbotfailed'  -or
          $Messages.Code -contains 'assertuserfailed'
        )

        if ($Disconnected -and $IgnoreDisconnect -eq $false)
        {
          # Create a local copy as Disconnect-MWSession will clear the original copy
          #$LocalCopy = $script:Config | Copy-Object

          $Retry = $true

          $ReconParams = @{
            Persistent = $script:Config.Persistent
          }

          if ($script:Config.Persistent)
          { Write-Warning 'The session has expired and is automatically being refreshed...' }
          else
          { Write-Warning 'The session has expired! Please sign in to continue, or press Ctrl + Z to abort.' }

          Disconnect-MWSession
          Connect-MWSession @ReconParams
        }

        if ($RateLimited)
        {
          $Retry = $true
          Write-Warning "Pausing execution to adhere to the rate limit."
          Start-Sleep -Seconds ($RateLimit + 5)
        }
      }
    } while ($Retry -and ++$Attempt -lt 3)

    if ($Attempt -eq 3)
    { Write-Warning 'Aborted after three failed attempt at retrying the request.' }

    return $JsonObject
  }

  End { }
}
#endregion

#region Move-MWPage
function Move-MWPage
{
  [CmdletBinding()]
  param (
    [Parameter(Mandatory, ValueFromPipelineByPropertyName, Position=0)]
    [Alias('Title', 'Identity', 'Path', 'Source', 'From')]
    [string]$Name,

    [Parameter(Mandatory, ValueFromPipelineByPropertyName, Position=1)]
    [Alias('Destination', 'Target', 'To')]
    [string]$NewName,

    [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
    [AllowEmptyString()]
    [string]$Reason,

    [switch]$NoRedirect,
    [switch]$SkipTalkPage,
    [switch]$SkipSubpages,
    [switch]$Force, # Ignores warnings
    [WatchList]$WatchList = [WatchList]::Preferences,
    
    <#
      Debug
    #>
    [switch]$JSON
  )

  Begin
  {
    $ArrJSON= @()
  }

  Process
  {
    if ($null -eq $script:Config.URI)
    {
      Write-Warning "Not connected to a MediaWiki instance."
      return $null
    }

    $Body = [ordered]@{
      action    = 'move'
      from      = $Name
      to        = $NewName
      reason    = $Reason
      watchlist = $WatchList.ToString().ToLower()
      token     = (Get-MWCsrfToken)
    }

    if ($NoRedirect)
    { $Body.noredirect = $true }

    if (-not $SkipTalkPage)
    { $Body.movetalk = $true }

    if (-not $SkipSubpages)
    { $Body.movesubpages = $true }

    if ($Force)
    { $Body.ignorewarnings = $true }

    $ArrJSON += Invoke-MWApiRequest -Body $Body -Method POST
  }

  End
  {
    if ($JSON)
    { return $ArrJSON}

    $ArrPSCustomObject = @()
    ForEach ($Page in $ArrJSON.move)
    {
      $ObjectProperties = [ordered]@{
        Source          = $Page.from
        Destination     = $Page.to
        Reason          = $Page.reason
        Redirect        = $Page.redirectcreated
        Subpages        = $Page.subpages
        SubpagesTalk    = $Page.'subpages-talk'
      }

      $ArrPSCustomObject += New-Object PSObject -Property $ObjectProperties
    }
    return $ArrPSCustomObject
  }
}
#endregion

#region New-MWPage
function New-MWPage
{
  [CmdletBinding()]
  param (
    <#
      Core parameters
    #>
    [Parameter(Mandatory, ValueFromPipelineByPropertyName, Position=0)]
    [ValidateNotNullOrEmpty()]
    [Alias('Title', 'Identity', 'PageName')]
    [string]$Name,

    [Parameter(ValueFromPipelineByPropertyName, Position=1)]
    [Alias("Text")]
    [string]$Content,

    [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
    [AllowEmptyString()]
    [string]$Summary,

    <#
      Watchlist
    #>
    [WatchList]$WatchList = [WatchList]::Preferences,

    <#
      Page related stuff
    #>
    [switch]$Recreate,

    <#
      Tags applied to the edit
    #>
    [switch]$Bot,
    [switch]$Minor,
    [switch]$Major,
    [string[]]$Tags, # Tag the edit according to a tag available in Special:Tags

    <#
      Debug
    #>
    [switch]$JSON
  )

  Begin { }

  Process
  {
    if ($null -eq $script:Config.URI)
    {
      Write-Warning "Not connected to a MediaWiki instance."
      return $null
    }

    $Params = @{
      Name       = $Name
      Content    = $Content
      WatchList  = $WatchList
      CreateOnly = $true
    }

    if ($Summary)
    { $Params.Summary = $Summary }

    if ($Recreate)
    { $Params.Recreate = $Recreate }

    if ($Bot)
    { $Params.Bot = $Bot }

    if ($Minor)
    { $Params.Minor = $Minor }

    if ($Major)
    { $Params.Major = $Major }

    if ($Tags)
    { $Params.Tags = $Tags }

    if ($JSON)
    { $Params.JSON = $true }

    return Set-MWPage @Params
  }

  End { }
}
#endregion

#region Remove-MWPage
function Remove-MWPage
{
  [CmdletBinding(DefaultParameterSetName = 'PageName')]
  param (
    <#
      Core parameters
    #>
    [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName, ParameterSetName = 'PageName', Position=0)]
    [ValidateNotNullOrEmpty()]
    [Alias("Title", "Identity", "PageName")]
    [string[]]$Name,

    [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName, ParameterSetName = 'PageID', Position=0)]
    [Alias("PageID")]
    [int[]]$ID,

    [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
    [AllowEmptyString()]
    [string]$Reason,

    <#
      Watchlist
    #>
    [WatchList]$WatchList = [WatchList]::Preferences,

    <#
      Debug
    #>
    [switch]$JSON
  )

  Begin
  {
    $ArrJSON = @()
  }

  Process
  {
    if ($null -eq $script:Config.URI)
    {
      Write-Warning "Not connected to a MediaWiki instance."
      return $null
    }

    [String[]]$Pages   = @()

    if ($ID)
    { $Pages = $ID }
    else
    { $Pages = $Name }

    ForEach ($Page in $Pages)
    {
      $Body = [ordered]@{
        action    = 'delete'
        reason    = $Reason
        watchlist = $WatchList.ToString().ToLower()
        token     = (Get-MWCsrfToken)
      }

      if ($ID)
      { $Body.pageid = $Page }
      else
      { $Body.title = $Page }

      $ArrJSON += Invoke-MWApiRequest -Body $Body -Method POST
    }
  }

  End
  {
    if ($JSON)
    { return $ArrJSON }

    $ArrPSCustomObject = @()
    ForEach ($Page in $ArrJSON.delete)
    {

      $ObjectProperties = [ordered]@{
        Name            = $Page.delete.title
        Reason          = $Page.delete.reason
        LogID           = $Page.delete.logid
      }

      $ArrPSCustomObject += New-Object PSObject -Property $ObjectProperties
    }
    return $ArrPSCustomObject
  }
}
#endregion

#region Search-MWPage
# Not to be mistaken for Find-MWPage!
function Search-MWPage
{
  [CmdletBinding(DefaultParameterSetName = 'SearchByText')]
  param
  (
    [parameter(Mandatory, ValueFromPipelineByPropertyName, Position=0)]
    [ValidateNotNullOrEmpty()]
    [Alias('String')]
    [string]$Pattern, # The pattern/search query to search for

    [ValidateScript({ Test-MWNamespace -InputObject $PSItem -AllowWildcard })]
    [string[]]$Namespace,

    # Default: size|wordcount|timestamp|snippet
    [ValidateSet('', '*', 'CategorySnippet', 'ExtensionData', 'IsFileMatch', 'RedirectSnippet', 'RedirectTitle', 'SectionSnippet', 'SectionTitle', 'Size', 'Snippet', 'Timestamp', 'TitleSnippet', 'WordCount')]
    [string[]]$Properties = @('Size', 'WordCount', 'Timestamp', 'Snippet'), # Comma-separated list of additional properties to include: categorysnippet, extensiondata, isfilematch, redirectsnippet, redirecttitle, sectionsnippet, sectiontitle, size, snippet, timestamp, titlesnippet, wordcount
    # Obsolete: hasrelated, score

    # Search Type (srwhat)
    [Parameter(ParameterSetName = 'SearchByText')]
    [switch]$Text,          # Search by Text (default)
    [Parameter(ParameterSetName = 'SearchByTitle')]
    [switch]$Title,         # Search by Title
    [Parameter(ParameterSetName = 'SearchByNearMatch')]
    [switch]$NearMatch,     # Search by NearMatch
    
    [switch]$AllowEmphasis,

    [ValidateScript({ Test-MWResultSize -InputObject $PSItem })]
    [string]$ResultSize = 1000,

    [uint32]$Offset = 0, # The query offset. The value must be no less than 0.

    <#
      Debug
    #>
    [switch]$JSON
  )

  Begin
  {
    $ArrJSON           = @()
    $ArrPSCustomObject = @()
  }

  Process
  {
    if ($null -eq $script:Config.URI)
    {
      Write-Warning "Not connected to a MediaWiki instance."
      return $null
    }

    if ($ResultSize -eq 'Unlimited')
    { $ResultSize = [int32]::MaxValue } # int32 because of Select-Object -First [int32]
    
    $Body = [ordered]@{
      action   = 'query'
      list     = 'search'
      srlimit  = 'max'
      srsearch = $Pattern
      sroffset = $Offset
    }

    # Use $_Namespace because PowerShell is being really odd at times,
    #   and seemingly executing Test-MWNamespace _after_ we are already within the function...
    $_Namespace = ConvertTo-MWNamespaceID $Namespace

    if (-not [string]::IsNullOrEmpty($_Namespace))
    { $Body.srnamespace = $_Namespace }

    if ($Title)
    { $Body.srwhat = 'title' }
    elseif ($NearMatch)
    { $Body.srwhat = 'nearmatch' }
    else
    { $Body.srwhat = 'text' } # default

    if (-not [string]::IsNullOrEmpty($Properties))
    {
      # Convert everything to lowercase
      $Properties = $Properties.ToLower()

      # Does it include a wildcard?
      if ($Properties -contains '*')
      { $Properties = @('CategorySnippet', 'ExtensionData', 'IsFileMatch', 'RedirectSnippet', 'RedirectTitle', 'SectionSnippet', 'SectionTitle', 'Size', 'Snippet', 'Timestamp', 'TitleSnippet', 'WordCount') }

      $Body.srprop = ($Properties -join '|')
    }

    $ArrJSON += Invoke-MWApiContinueRequest -Body $Body -Method GET -ResultSize $ResultSize -Node1 'search'
  }

  End
  {
    if ($JSON)
    { return $ArrJSON }

    $ArrPSCustomObject = (($ArrJSON.query.search | Select-Object -First $ResultSize) | ForEach-Object { ConvertFrom-HashtableToPSObject $_ })

    if ($AllowEmphasis -eq $false)
    {
      # The query term highlighting markup seems to be:
      # <span class='searchmatch'><query></span>
      $EmphasisRegEx = "<span class='searchmatch'>(.*?)</span>"

      foreach ($PSCustomObject in $ArrPSCustomObject)
      {
        if (-not ([string]::IsNullOrEmpty($PSCustomObject.Snippet)))
        { $PSCustomObject.Snippet         = $PSCustomObject.Snippet         -replace $EmphasisRegEx, '$1' }

        if (-not ([string]::IsNullOrEmpty($PSCustomObject.TitleSnippet)))
        { $PSCustomObject.TitleSnippet    = $PSCustomObject.TitleSnippet    -replace $EmphasisRegEx, '$1' }

        if (-not ([string]::IsNullOrEmpty($PSCustomObject.RedirectSnippet)))
        { $PSCustomObject.RedirectSnippet = $PSCustomObject.RedirectSnippet -replace $EmphasisRegEx, '$1' }

        if (-not ([string]::IsNullOrEmpty($PSCustomObject.SectionSnippet)))
        { $PSCustomObject.SectionSnippet  = $PSCustomObject.SectionSnippet  -replace $EmphasisRegEx, '$1' }

        if (-not ([string]::IsNullOrEmpty($PSCustomObject.CategorySnippet)))
        { $PSCustomObject.CategorySnippet = $PSCustomObject.CategorySnippet -replace $EmphasisRegEx, '$1' }
      }
    }

    return $ArrPSCustomObject
  }
}
#endregion

#region Set-MWPage
function Set-MWPage
{
  [CmdletBinding(DefaultParameterSetName = 'PageName')]
  param (
    <#
      Core parameters
    #>
    [Parameter(Mandatory, ValueFromPipelineByPropertyName, ParameterSetName = 'PageName', Position=0)]
    [ValidateNotNullOrEmpty()]
    [Alias('Title', 'Identity', 'PageName')]
    [string]$Name,

    [Parameter(Mandatory, ValueFromPipelineByPropertyName, ParameterSetName = 'PageID', Position=0)]
    [Alias("PageID")]
    [uint32]$ID,

    [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
    [AllowEmptyString()]
    [string]$Summary,

    [Parameter(ValueFromPipelineByPropertyName)]
    [Alias("Text")]
    [string]$Content,

    <#
      Section based stuff
    #>
    [Alias("Header")]
    [switch]$Section,

    [Alias("HeaderTitle")]
    [string]$SectionTitle,

    [Alias("HeaderID")]
    $SectionID = $null,

    <#
      Append / Prepend
    #>
    [Alias('AppendText')]
    [switch]$Append,

    [Alias('PrependText')]
    [switch]$Prepend,

    <#
      Verification
    #>
    [Alias("BaseRevID")]
    [uint32]$BaseRevisionID,

    [string]$BaseTimestamp,
    
    [string]$StartTimestamp,

    <#
      Watchlist
    #>
    [WatchList]$WatchList = [WatchList]::Preferences,

    <#
      Page related stuff
    #>
    [switch]$Recreate,
    [switch]$CreateOnly,
    [switch]$NoCreate,

    <#
      Tags applied to the edit
    #>
    [switch]$Bot,
    [switch]$Minor,
    [switch]$Major,
    [switch]$Redirect,
    [string[]]$Tags, # Tag the edit according to a tag available in Special:Tags

    <#
      Debug
    #>
    [switch]$JSON
  )

  Begin { }

  Process
  {
    if ($null -eq $script:Config.URI)
    {
      Write-Warning "Not connected to a MediaWiki instance."
      return $null
    }

    $PSCustomObject = @()
    $JoinedTags     = ''

    if ($PSBoundParameters.ContainsKey('Tags'))
    { $JoinedTags = $Tags -join '|' }

    $Page = $null

    $Body = [ordered]@{
      action    = 'edit'
      summary   = $Summary
      watchlist = $WatchList.ToString().ToLower()
      token     = (Get-MWCsrfToken)
    }

    $Identity = ''

    if ($ID)
    {
      $Identity    = $ID
      $Body.pageid = $ID
    }
    else
    {
      $Identity   = $Name
      $Body.title = $Name
    }

    if ($Section)
    {
      if ($null -ne $SectionID)
      { $Body.section = $SectionID } # Assume section id (or 'new')
      else
      { $Body.section = 'new' } # Omit if false

      if ($SectionTitle)
      { $Body.sectiontitle = $SectionTitle }
    }

    if ($Recreate)
    { $Body.recreate = $true } # Omit if false

    if ($CreateOnly)
    { $Body.createonly = $true } # Omit if false

    if ($NoCreate)
    { $Body.nocreate = $true } # Omit if false

    if ($Bot)
    { $Body.bot = $true } # Omit if false

    if ($Redirect)
    { $Body.redirect = $true } # Automatically resolve redirects. Omit if false

    if ($Major)
    { $Body.notminor = $true } # Omit if false
    elseif ($Minor)
    { $Body.minor = $true } # Omit if false
    else
    { } # Default to user preference

    if (-not [string]::IsNullOrEmpty($JoinedTags))
    { $Body.tags = $JoinedTags }

    if ($Append)
    { $Body.appendtext = $Content }
    elseif ($Prepend)
    { $Body.prependtext = $Content }
    else
    { $Body.text = $Content }

    if ($BaseRevisionID)
    { $Body.baserevid = $BaseRevisionID }

    if ($BaseTimestamp)
    { $Body.basetimestamp = $BaseTimestamp }

    if ($StartTimestamp)
    { $Body.starttimestamp = $StartTimestamp }

    Write-Verbose "Editing page $Identity."

    $Response = Invoke-MWApiRequest -Body $Body -Method POST

    if ($JSON)
    { return $Response }

    # TODO: Translate to PSCustomObject?

    if ($Page = $Response.edit)
    {
      if ($Page.result -eq 'Success')
      {
        $ObjectProperties = [ordered]@{
         #Namespace          = $Page.ns
          ID                 = $Page.pageid
          Name               = $Page.title
          ContentModel       = $Page.contentmodel
          RevisionID         = $Page.newrevid
          PreviousRevisionID = $Page.oldrevid
          Timestamp          = $Page.newtimestamp
        }

        if ($null -ne $Page.new)
        {
          Write-Warning "'$($Page.title)' was created as a result of this edit."
          $ObjectProperties.New = $true
        }

        if ($null -ne $Page.nochange)
        {
          Write-Warning "No change was made to '$($Page.title)'."
          $ObjectProperties.NoChange = $true
        }

        $PSCustomObject = New-Object PSObject -Property $ObjectProperties
      }
      else
      { Write-Warning "Error editing page $Identity." }
    }

    return $PSCustomObject
  }

  End { }
}
#endregion

#region Update-MWPage
# TODO: Rethink, reevaluate, redesign, reimplement
function Update-MWPage
{
  [CmdletBinding(DefaultParameterSetName = 'PageName')]
  param (
    <#
      Core parameters
    #>
    [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName, ParameterSetName = 'PageName', Position=0)]
    [ValidateNotNullOrEmpty()]
    [Alias('Title', 'Identity', 'PageName')]
    [string[]]$Name,

    [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName, ParameterSetName = 'PageID', Position=0)]
    [Alias('PageID')]
    [int[]]$ID,

    [uint32]$Limit = 30,
    [uint32]$Offset = 0,
    [switch]$ForceLinkUpdate,
    [switch]$ForceRecursiveLinkUpdate,
    [switch]$NoWait,
    [switch]$NullEdit,

    <#
      Debug
    #>
    [switch]$JSON
  )

  Begin
  {
    $ArrJSON           = @()
    $ArrPSCustomObject = @()
  }

  Process
  {
    if ($null -eq $script:Config.URI)
    {
      Write-Warning "Not connected to a MediaWiki instance."
      return $null
    }

    [String[]]$Identities = @()
    
    if ($Name)
    { $Identities = $Name }

    if ($ID)
    { $Identities = $ID }
    
    [String[]]$PagesFull = $Identities
    $Max = 1

    Write-Host $Max, $Limit, $Offset
    Write-Host $Identities

    if ($null -ne $PagesFull.Count)
    { $Max = $PagesFull.Count }

    $Body = [ordered]@{
      action    = 'purge'
      redirects = $true # Omit if false
    }

    if ($ForceLinkUpdate)
    { $Body.forcelinkupdate = $true } # Omit if false

    if ($ForceRecursiveLinkUpdate)
    { $Body.forcerecursivelinkupdate = $true } # Omit if false

    do
    {
      if ($Max -gt $Limit)
      { Write-Progress -Activity "Purge in progress" -Status "$Offset pages completed..." -PercentComplete ($Offset / $Max * 100) }

      $PagesLimited = @()
      $ArrTemp      = @()
      $WebRequest   = $null
      $Purged       = $null

      for ($i = $Offset; $i -lt ($Offset + $Limit) -and $i -lt $Max; $i++)
      { $PagesLimited += $PagesFull[$i] }

      if ($NullEdit)
      {
        Write-Verbose "[Update-MWPage] Performing null edits..."

        ForEach ($Page in $PagesLimited)
        {
          $Result = $null

          if ($Name)
          { $Result = Set-MWPage -Name $Page -Content "" -Summary "" -Append -Bot -NoCreate -JSON -WarningAction:SilentlyContinue } else {
            $Result = Set-MWPage   -ID $Page -Content "" -Summary "" -Append -Bot -NoCreate -JSON -WarningAction:SilentlyContinue
          }

          $ObjectProperties = [ordered]@{
            Namespace = (Get-MWNamespace -NamespaceName (($Result.edit.title -split ':')[0])).Name
            Name      = $Result.edit.title
            ID        = $Result.edit.pageid
          }

          $ObjectProperties += [ordered]@{
            Purged    = ($null -ne $Result.edit.result -and $Result.edit.result -eq 'Success')
           #Missing   = $null
          }

          if ($null -ne $Result.error.code -and $Result.error.code -eq 'missingtitle')
          {
          #$ObjectProperties.Missing = $true
            $ObjectProperties.Missing   = $true

            Write-Warning "The page '$Page' does not exist."
          }

          $PageObject         = New-Object PSObject -Property $ObjectProperties
          $ArrPSCustomObject += $PageObject
          $ArrTemp           += $PageObject
        }

        $Purged = $ArrTemp | Where-Object { $_.Purged -eq $true -or $_.Missing -eq $true }

        if ($null -ne $Purged)
        {
          if ($Purged.Count)
          { $Purged = $Purged.Count }
          else
          { $Purged = 1 }
        }
        else
        { $Purged = 0 }

        $Offset = $Offset + $Purged

      } else { # Original implementation

        if ($Name)
        { $Body.titles  = ($PagesLimited -join '|') }
        else
        { $Body.pageids = ($PagesLimited -join '|') }

        Write-Verbose "[Update-MWPage] Sending payload: $($PagesLimited -join '|')"

        Write-Host ((Get-MWUserInfo).RateLimits.purge.ip.seconds)

        $WebRequest = Invoke-MWApiRequest -Body $Body -Method POST -RateLimit ((Get-MWUserInfo).RateLimits.purge.ip.seconds)

        if ($WebRequest)
        {
          $ArrJSON += $WebRequest

          ForEach ($Page in $WebRequest.purge)
          {
            $ObjectProperties = [ordered]@{
              Namespace = (Get-MWNamespace -NamespaceID $Page.ns).Name
            }

            if ($Page.title)
            { $ObjectProperties.Name = $Page.title } else {
              $ObjectProperties.ID = $Page.id
            }

            $ObjectProperties += [ordered]@{
              Purged    = ($null -ne $Page.purged)
             #Missing   = $null
            }

            if ($null -ne $Page.missing)
            {
            #$ObjectProperties.Missing = $true
              $ObjectProperties.Missing   = $true

              Write-Warning "The page '$($Page.title)$($Page.pageid)' does not exist."
            }

            if ($ForceLinkUpdate -or $ForceRecursiveLinkUpdate)
            { $ObjectProperties.LinkUpdated = ($null -ne $Page.linkupdate) }

            $PageObject         = New-Object PSObject -Property $ObjectProperties
            $ArrPSCustomObject += $PageObject
            $ArrTemp           += $PageObject
          }

          $Purged = $ArrTemp | Where-Object { $_.Purged -eq $true -or $_.Missing -eq $true }

          if ($null -ne $Purged)
          {
            if ($Purged.Count)
            { $Purged = $Purged.Count }
            else
            { $Purged = 1 }
          }
          else
          { $Purged = 0 }

          $Offset = $Offset + $Purged
        }
      }

      if ($NoWait -eq $false -and $Offset -lt $Max)
      {
        Write-Verbose "[Update-MWPage] $Offset/$Max have been purged so far."
        Write-Progress -Activity "Purge in progress" -Status "$Offset pages completed..." -PercentComplete ($Offset / $Max * 100)

        if ($NullEdit -eq $false)
        {
          Write-Warning "Estimated time remaining: ~$([math]::Round((($Max - $Offset) / $Limit) + 1)) minutes..."
          #Start-Sleep -Seconds 65
        }
      }
    } while ($NoWait -eq $false -and $Offset -lt $Max)

    Write-Progress -Activity "Purge in progress" -Status "Ready" -Completed
  }

  End
  {
    if ($JSON)
    { return $ArrJSON }

    # Remove duplicates where purge failed in one loop but succeeded in the next loop, as the failed result is not of interest
    $NewArrPSCustomObject  = @()
    ForEach ($Page in $ArrPSCustomObject)
    {
      $Count = 0
      $Items = $ArrPSCustomObject | Where-Object Name -eq $Page.Name
      if ($Items.Count) { $Count = $Items.Count } else { $Count = 1 }

      # IF this is the only match OR the match indicates the purge is complete THEN add it to the list
      if ($Count -eq 1 -or $Page.Purged -eq $true)
      { $NewArrPSCustomObject += $Page }
    }

    return $NewArrPSCustomObject
  }
}
#endregion

#region Watch-MWPage
# TODO: Implement
# Change: https://www.mediawiki.org/wiki/API:Edit
# Get:    https://www.mediawiki.org/wiki/API:Watchlist
function Watch-MWPage
{
  throw 'Not implemented'
}
#endregion