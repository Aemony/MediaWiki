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

# - Supported parameter values can be retrieved through Get-MWAPIModule, e.g.
#     (Get-MWAPIModule -Properties parse).paraminfo.modules.parameters | where name -eq 'prop').type
#  
# Long-term potential TODO (lol); change $Properties and the like to be based on values
#   obtained through Get-MWAPIModule...
























# --------------------------------------------------------------------------------------- #
#                                                                                         #
#                                      GLOBAL STUFF                                       #
#                                                                                         #
# --------------------------------------------------------------------------------------- #

# Enum used to indicate watchlist parameter value for cmdlets
enum Watchlist
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

# Enum used to indicate token type for Get-MWToken
enum TokenType
{
  None
  CSRF
  Patrol
  Rollback
  UserRights
  Watch
}

# Unset all variables when the module is being removed from the session
$MyInvocation.MyCommand.ScriptBlock.Module.OnRemove = { Clear-MWSession }

# Global configurations
$script:ProgressPreference = 'SilentlyContinue' # Suppress progress bar (speeds up Invoke-WebRequest by a ton)

# Global variable to hold the web session
$global:MWSession

# Script variable to indicate the location of the saved config file
$script:ConfigFileName = $env:LOCALAPPDATA + '\PowerShell\MediaWiki\config.json'

# Script variables used internally during runtime
$script:MWSessionGuest = $false
$script:MWSessionBot   = $false
$script:MWTokens       = @{
  CreateAccount        = $null
  CSRF                 = $null # Cross-site request forgery (CSRF)
  Patrol               = $null
  Rollback             = $null # Rollback token
  UserRights           = $null
  Watch                = $null
}
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
  dbrepllag                   = 'DatabaseReplicationLag'
    host                        = 'Host'
    lag                         = 'Lag'
  defaultoptions              = 'DefaultOptions'
   'email-allow-new-users'      = 'AllowMailFromNewUsers'
  # usebetatoolbar              = 'UseEnhancedToolbar'        # WikiEditor 2010: Enhanced editing toolbar
  #'usebetatoolbar-cgd'         = 'UseEnhancedToolbarDialogs' # WikiEditor 2010: Enhanced toolbar dialogs/link and table wizards
  extensions                  = 'Extensions'
    namemsg                     = 'NameMessage'
    credits                     = 'Credits'
    descriptionmsg              = 'DescriptionMessage'
    license                     = 'License'
   'license-name'               = 'LicenseName'
    version                     = 'Version'
   'vcs-date'                   = 'VcsDate'
   'vcs-system'                 = 'VcsSystem'
   'vcs-version'                = 'VcsVersion'
   'vcs-url'                    = 'VcsUrl'
  extensiontags               = 'ExtensionTags'
  fileextensions              = 'FileExtensions'
    ext                         = 'Ext'
  functionhooks               = 'FunctionHooks'
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
    generator                   = 'Generator'
    imagelimits                 = 'ImageLimits'
    imagewhitelistenabled       = 'ImageWhitelistEnabled'
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
  interwikimap                = 'InterwikiMap'
    protorel                    = 'ProtocolRelative'
  libraries                   = 'Libraries'
  magicwords                  = 'MagicWords'
   'case-sensitive'             = 'CaseSensitive'
  protocols                   = 'Protocols'
  rightsinfo                  = 'RightsInfo'
  skins                       = 'Skins'
    default                     = 'Default'
    unusable                    = 'Unusable'
  showhooks                   = 'ShowHooks'
    subscribers                 = 'Subscribers'
  languages                   = 'Languages'
    bcp47                       = 'Bcp47'
  languagevariants            = 'LanguageVariants'
    fallbacks                   = 'Fallbacks'
  statistics                  = 'Statistics'
    activeusers                 = 'ActiveUsers'
    admins                      = 'Admins'
    articles                    = 'Articles'
    edits                       = 'Edits'
    jobs                        = 'Jobs'
    users                       = 'Users'
  uploaddialog                = 'UploadDialog'
    fields                      = 'Fields'
    format                      = 'Format'
      filepage                    = 'FilePage'
      ownwork                     = 'IsOwnWork'
      uncategorized               = 'Uncategorized'
    licensemessages             = 'LicenseMessages'
      foreign                     = 'Foreign'
  usergroups                  = 'UserGroups'
  variables                   = 'Variables'

  name                        = 'Name'
  author                      = 'Author'
  ISBN                        = 'ISBN'
  PMID                        = 'PMID'
  RFC                         = 'RFC'
  captionLength               = 'CaptionLength'
  height                      = 'Height'
  imageHeight                 = 'ImageHeight'
  width                       = 'Width'
  imageWidth                  = 'ImageWidth'
  imagesPerRow                = 'ImagesPerRow'
  mode                        = 'Mode'
  showBytes                   = 'ShowBytes'
  showDimensions              = 'ShowDimensions'

  <# Aliases #>
  alias                       = 'Alias'
  aliases                     = 'Aliases'
  namespacealiases            = 'NamespaceAliases'
  specialpagealiases          = 'SpecialPageAliases'

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
  anon                        = 'Anonymous'                      # Renamed
  messages                    = 'Messages'
  unreadcount                 = 'UnreadCount'
  editcount                   = 'EditCount'
  latestcontrib               = 'LatestContribution'             # Renamed
  groups                      = 'Groups'
  rights                      = 'Rights'

  # Rate Limits
  ratelimits                  = 'RateLimits'
    changeemail                 = 'ChangeEmail'
    confirmemail                = 'ConfirmEmail'
    changetag                   = 'ChangeTag'
    editcontentmodel            = 'EditContentModel'
    emailuser                   = 'EmailUser'
    mailpassword                = 'MailPassword'
    move                        = 'Move'
    purge                       = 'Purge'
    linkpurge                   = 'LinkPurge'
    renderfile                  = 'RenderFile'
   'renderfile-nonstandard'     = 'RenderFileNonStandard'
    rollback                    = 'Rollback'
    stashedit                   = 'StashEdit'
   'thanks-notification'        = 'ThanksNotification'           # Renamed
    upload                      = 'Upload'

  user                        = 'User'
  ip                          = 'IP'
  hits                        = 'Hits'
  seconds                     = 'Seconds'
  attachedlocal               = 'AttachedLocal'
  local                       = 'Local'
  centralids                  = 'CentralIDs'
  changeablegroups            = 'ChangeableGroups'
    add                         = 'Add'
   'add-self'                   = 'AddSelf'                      # Renamed
    remove                      = 'Remove'
   'remove-self'                = 'RemoveSelf'                   # Renamed
  email                       = 'Email'
  groupmemberships            = 'GroupMemberships'
  implicitgroups              = 'ImplicitGroups'
  options                     = 'Options'                        # Options are as varied as the extesions installed, so only pascal case some of them...
    # User Profile
    fancysig                    = 'FancySig' # If User uses a custom (raw) signature (0 or 1). If user has specified a custom sig, the actual text of the signature is in the nickname option.
    nickname                    = 'Nickname' # Custom signature
    enotifwatchlistpages        = 'ENotifWatchlistPages'
    enotifusertalkpages         = 'ENotifUserTalkPages'
    enotifminoredits            = 'ENotifMinorEdits'
    enotifrevealaddr            = 'ENotifRevealAddr'
    gender                      = 'Gender'
    realname                    = 'RealName'
    language                    = 'Language'
    disablemail                 = 'DisableMail'
    # Skin
    skin                        = 'Skin'
    # Files
    imagesize                   = 'ImageSize'
    thumbsize                   = 'Thumbsize'
    # Date and Time
    date                        = 'Date'
    timecorrection              = 'TimeCorrection'
    # Editing
    editfont                    = 'EditFont'
    editondblclick              = 'EditOnDblClick'
    editsectiononrightclick     = 'EditSectionOnRightClick'
    forceeditsummary            = 'ForceEditSummary'
    previewonfirst              = 'PreviewOnFirst'
    previewontop                = 'PreviewOnTop'
    minordefault                = 'MinorDefault'
    useeditwarning              = 'UseEditWarning'
    uselivepreview              = 'UseLivePreview'
    # Recent Changes
    rcdays                      = 'RcDays'
    rclimit                     = 'RcLimit'
    hidecategorization          = 'HideCategorization'
    hideminor                   = 'HideMinor'
    hidepatrolled               = 'HidePatrolled'
    newpageshidepatrolled       = 'NewPagesHidePatrolled'
    shownumberswatching         = 'ShowNumbersWatching'
    usenewrc                    = 'UseNewRc'
    # Watchlist
    extendwatchlist             = 'ExtendWatchlist' # Expand watchlist to show all applicable changes
    watchcreations              = 'WatchCreations'
    watchdefault                = 'WatchDefault'
    watchdeletion               = 'WatchDeletion'
    watchlistdays               = 'WatchlistDays'
    watchlisthideanons          = 'WatchlistHideAnons'
    watchlisthidebots           = 'WatchlistHideBots'
    watchlisthidecategorization = 'WatchlistHideCategorization'
    watchlisthideliu            = 'WatchlistHideLIU' # Hide Logged In User
    watchlisthideminor          = 'WatchlistHideMinor'
    watchlisthideown            = 'WatchlistHideOwn'
    watchlisthidepatrolled      = 'Watchlist'
    watchlistreloadautomatically= 'WatchlistReloadAutomatically'
    watchlistunwatchlinks       = 'WatchlistUnwatchLinks'
    watchmoves                  = 'WatchMoves'
    watchrollback               = 'WatchRollback'
    watchuploads                = 'WatchUploads'
    wllimit                     = 'WlLimit' # Number of edits to show in expanded watchlist (if 'extendwatchlist' == 1) 
    # Misc
    ccmeonemails                = 'CCMeOnEmails'
    diffonly                    = 'DiffOnly'
    norollbackdiff              = 'NoRollbackDiff'
    numberheadings              = 'NumberHeadings'
    prefershttps                = 'PrefersHTTPS'
    requireemail                = 'RequireEmail'
    showhiddencats              = 'ShowHiddenCats'
    showrollbackconfirmation    = 'ShowRollbackConfirmation'
    stubthreshold               = 'StubThreshold'
    underline                   = 'Underline'

  <# Users #>
  attachedwiki                = 'AttachedWiki'
  emailable                   = 'Emailable'
  expiry                      = 'Expiry'
  group                       = 'Group'
  registration                = 'Registration'

  <# Pages #>
  id                          = 'ID'                             # Potential conflict with PageID ?
  ns                          = 'Namespace'                      # Renamed
  pageid                      = 'ID'                             # Renamed
  title                       = 'Name'                           # Renamed
  displaytitle                = 'DisplayTitle'
  touched                     = 'LastModified'                   # Renamed
  revid                       = 'RevisionID'                     # Renamed
  lastrevid                   = 'LastRevisionID'                 # Renamed
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
  wikitext                    = 'Wikitext'
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

  <# Change Tags #>
  active                      = 'Active'
  defined                     = 'Defined'
  description                 = 'Description'
  displayname                 = 'DisplayName'
  hitcount                    = 'HitCount'

  <# Upload #>
  result                      = 'Result'
  filekey                     = 'FileKey'
  sessionkey                  = 'SessionKey'

  <# API Modules #>
  classname                   = 'ClassName'
  dynamicparameters           = 'DynamicParameters'
  examples                    = 'Examples'
  helpurls                    = 'HelpUrls'
  licenselink                 = 'LicenseLink'
  licensetag                  = 'LicenseTag'
  mustbeposted                = 'MustBePosted'
  parameters                  = 'Parameters'
    allowsduplicates            = 'AllowsDuplicates'
    allspecifier                = 'AllSpecifier'
    deprecated                  = 'Deprecated'
    deprecatedvalues            = 'DeprecatedValues'
    highlimit                   = 'HighLimit'
    highmax                     = 'HighMax'
    limit                       = 'Limit'
    lowlimit                    = 'LowLimit'
    max                         = 'Max'
    min                         = 'Min'
    multi                       = 'Multi'
    required                    = 'Required'
    sensitive                   = 'Sensitive'
    subtypes                    = 'SubTypes'
    tokentype                   = 'TokenType'
  path                        = 'Path'
  readrights                  = 'ReadRights'
  info                        = 'Info'
  internal                    = 'Internal'
  extranamespaces             = 'ExtraNamespaces'
  slot                        = 'Slot'
  sourcename                  = 'SourceName'
  submodules                  = 'SubModules'
  submoduleparamprefix        = 'SubModuleParameterPrefix'
  templatedparameters         = 'TemplatedParameters'
    templatevars                = 'TemplateVariables'
  values                      = 'Values'
  writerights                 = 'WriteRights'

  <# Debug #>
  curtimestamp                = 'ServerTimestamp'                # Current server timestamp / Retrieved

  <# Internals #>
  NamespaceID                 = 'NamespaceID'
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
        { Write-Verbose "Missing pascal case for: $Key" }

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

#region Test-MWChangeTag
function Test-MWChangeTag
{
<#
  .SYNOPSIS
    Validation helper used to ensure the input is a valid change tag.
  .DESCRIPTION
    When used to validate a [string] parameter, the input object will only
    be allowed if it matches a valid change tag.
  .PARAMETER InputObject
    An object to perform the validation on.
  .EXAMPLE
    [ValidateScript({ Test-MWChangeTag -InputObject $PSItem })]
    [string[]]$Tags
#>
  [CmdletBinding()]
  param (
    [Parameter(Mandatory)]
    $InputObject
  )

  if ($InputObject -in $script:Cache.ChangeTag)
  { $true }
  else
  { throw ('The argument "' + $InputObject + '" does not belong to the set "' + ($script:Cache.ChangeTag -join ',') + '". Supply an argument that is in the set and then try the command again.') }
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

#region Set-Substring
Set-Alias -Name Replace-Substring -Value Set-Substring
function Set-Substring
{
<#
  .SYNOPSIS
    String helper used to replace the nth occurrence of a substring.
  .DESCRIPTION
    Function used to replace the nth occurrence of a substring within a given string,
    using an optional string comparison type.
  .PARAMETER InputObject
    String to act upon.
  .PARAMETER Substring
    Substring to search for.
  .PARAMETER NewSubstring
    The new substring to replace the found substring with.
  .PARAMETER Occurrence
    The nth occurrence to replace. Defaults to first occurrence.
  .PARAMETER Comparison
    The string comparison type to use. Defaults to InvariantCultureIgnoreCase.
  .EXAMPLE
    $ContentBlock | Set-Substring -Substring $Target -NewSubstring $NewSection -Occurrence -1
  .INPUTS
    String to act upon.
  .OUTPUTS
    Returns InputObject with the nth matching substring changed.
#>
  [CmdletBinding()]
  param(
    [Parameter(Mandatory, ValueFromPipeline)]
    [string]$InputObject,
    
    [Parameter(Mandatory, Position=0)]
    [string]$Substring,

    [Parameter(Mandatory, Position=1)]
    [Alias('Replacement')]
    [AllowEmptyString()]
    [string]$NewSubstring,

    [Parameter()]
       [int]$Occurrence = 0, # Positive: from start; Negative: from back.

    [Parameter()]
    [StringComparison]$Comparison = [StringComparison]::InvariantCultureIgnoreCase
  )
  
  Begin { }

  Process
  {
    $Index   = -1
    $Indexes = @()

    if ($Occurrence -gt 0)
    {
      $Occurrence--
    }

    do
    {
      $Index = $InputObject.IndexOf($Substring, 1 + $Index, $Comparison)
      if ($Index -ne -1)
      {
        $Indexes += $Index
      }
    } while ($Index -ne -1)

    if ($null  -ne   $Indexes[$Occurrence]) {
      $Index       = $Indexes[$Occurrence]
      $InputObject = $InputObject.Remove($Index, $Substring.Length).Insert($Index, $NewSubstring)
    } elseif ($Indexes.Count -gt 0) {
      Write-Verbose "The specified occurrence does not exist."
    } else {
      Write-Verbose "No matching substring was found."
    }

    return $InputObject
  }

  End { }
}
#endregion
































# --------------------------------------------------------------------------------------- #
#                                                                                         #
#                                         CMDLETs                                         #
#                                                                                         #
# --------------------------------------------------------------------------------------- #

#region Add-MWPage
function Add-MWPage
{
  <#
  .SYNOPSIS
    Appends content to an existing page.

  .DESCRIPTION
    Appends (or optionally prepends) content to an existing page.

  .PARAMETER Name
    Name of the page to edit. Cannot be used alongside the -ID parameter.

  .PARAMETER ID
    ID of the page to edit. Cannot be used alongside the -Name parameter.

  .PARAMETER Summary
    A short summary to attach to the edit.

  .PARAMETER Content
    Contents to add to the page.

  .PARAMETER NoNewline
    Switch used to indicate that no newline should be created before/after the new content.

  .PARAMETER Prepend
    Switch used to indicate that the specified -Content should be prepended to the page.

  .PARAMETER BaseRevisionID
    ID of the base revision, used to detect edit conflicts.

  .PARAMETER BaseTimestamp
    Timestamp of the base revision, used to detect edit conflicts.

  .PARAMETER StartTimestamp
    Timestamp when the editing process began, used to detect edit conflicts.

  .PARAMETER Watchlist
    Defines whether to add the page to the user's watchlist or not.

  .PARAMETER Bot
    Switch used to indicate the edit was performed by a bot.

  .PARAMETER Minor
    Switch used to indicate the edit is of a minor concern.

  .PARAMETER Minor
    Switch used to indicate the edit is of a major concern.

  .PARAMETER Tags
    Tag the edit according to one or more tags available in Special:Tags
    
  .INPUTS
    Name (System.String) of the page to edit. Cannot be used alongside the -ID parameter.

  .INPUTS
    ID (System.UInt32) of the page to edit. Cannot be used alongside the -Name parameter.

  .INPUTS
    Summary (System.String) of the edit summary.

  .OUTPUTS
    Returns a PSObject object containing the results of the edit.
  #>
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
    [Alias('PageID')]
    [uint32]$ID,

    [Parameter(ValueFromPipelineByPropertyName)]
    [AllowEmptyString()]
    [string]$Summary,

    [Parameter()]
    [AllowEmptyString()]
    [Alias('Text', 'Wikitext')]
    [string]$Content,

    [switch]$NoNewline,

    <#
      Append / Prepend
    #>
    #[Alias('AppendText')]
    #[switch]$Append, (default)

    [Alias('PrependText')]
    [switch]$Prepend,

    <#
      Verification
    #>
    [Alias('BaseRevID')]
    [uint32]$BaseRevisionID,
    [string]$BaseTimestamp,
    [string]$StartTimestamp,

    <#
      Watchlist
    #>
    [Watchlist]$Watchlist = [Watchlist]::Preferences,

    <#
      Tags applied to the edit
    #>
    [switch]$Bot,
    [switch]$Minor,
    [switch]$Major,
    [string[]]$Tags, # Tag the edit according to one or more tags available in Special:Tags

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

    if (-not $NoNewline -and -not [string]::IsNullOrWhiteSpace($Content))
    {
      if ($Prepend -and $Content -notmatch "\n$")
      { $Content = "$Content`n" }
      elseif ($Content -notmatch "^\n")
      { $Content = "`n$Content" }
    }

    $Parameters       = @{
      Name            = $Name
      Watchlist       = $Watchlist
      NoCreate        = $true
      FollowRedirects = $true
      JSON            = $JSON
    }

    if ($Prepend)
    { $Parameters.Prepend = $true }
    else
    { $Parameters.Append = $true }

    if ($Summary)
    { $Parameters.Summary = $Summary }

    if ($Content)
    { $Parameters.Content = $Content }

    if ($BaseRevisionID)
    { $Parameters.BaseRevisionID = $BaseRevisionID }

    if ($BaseTimestamp)
    { $Parameters.BaseTimestamp = $BaseTimestamp }

    if ($StartTimestamp)
    { $Parameters.StartTimestamp = $StartTimestamp }

    if ($Bot)
    { $Parameters.Bot = $Bot }

    if ($Minor)
    { $Parameters.Minor = $Minor }

    if ($Major)
    { $Parameters.Major = $Major }

    if ($Tags)
    { $Parameters.Tags = $Tags }

    return Set-MWPage @Parameters
  }

  End { }
}
#endregion

#region Add-MWSection
function Add-MWSection
{
  <#
  .SYNOPSIS
    Appends content to an existing section on the given page.

  .DESCRIPTION
    The cmdlet is a front for Set-MWPage that makes it easier to add new text to an existing section on pages.

  .PARAMETER Name
    Name of the page to edit. Cannot be used alongside the -ID parameter.

  .PARAMETER FromTitle
    Alias for the -Name parameter.

  .PARAMETER ID
    ID of the page to edit. Cannot be used alongside the -Name parameter.

  .PARAMETER Summary
    A short summary to attach to the edit.

  .PARAMETER Content
    Content to append to the specified section.

  .PARAMETER NoNewline
    Switch used to indicate that no newline should be created before/after the new content.

  .PARAMETER Index
    The section index to edit, retrieved through Get-MWPage.

  .PARAMETER Prepend
    Switch used to indicate that the content should be prepended before the header of the specified section.

  .PARAMETER BaseRevisionID
    ID of the base revision, used to detect edit conflicts.

  .PARAMETER BaseTimestamp
    Timestamp of the base revision, used to detect edit conflicts.

  .PARAMETER StartTimestamp
    Timestamp when the editing process began, used to detect edit conflicts.

  .PARAMETER Watchlist
    Defines whether to add the page to the user's watchlist or not.

  .PARAMETER FollowRedirects
    Switch to retrieve information about the target pages of any given redirect page, instead of the redirect page itself.

  .PARAMETER Bot
    Switch used to indicate the edit was performed by a bot.

  .PARAMETER Minor
    Switch used to indicate the edit is of a minor concern.

  .PARAMETER Minor
    Switch used to indicate the edit is of a major concern.

  .PARAMETER Tags
    Tag the edit according to one or more tags available in Special:Tags
    
  .INPUTS
    Name (System.String) of the page to edit. Cannot be used alongside the -ID parameter.
    
  .INPUTS
    FromTitle (System.String) as an alias for -Name.

  .INPUTS
    ID (System.UInt32) of the page to edit. Cannot be used alongside the -Name parameter.

  .INPUTS
    Summary (System.String) of the edit summary.

  .INPUTS
    Index (System.UInt32) of the section to edit.

  .OUTPUTS
    Returns a PSObject object containing the results of the edit.
  #>
  [CmdletBinding(DefaultParameterSetName = 'PageName')]
  param (
    <#
      Core parameters
    #>
    [Parameter(Mandatory, ValueFromPipelineByPropertyName, ParameterSetName = 'PageName', Position=0)]
    [ValidateNotNullOrEmpty()]
    [Alias('Title', 'Identity', 'PageName')]
    [string]$Name,

    # Alias for $Name, but in a way to support ValueFromPipelineByPropertyName
    [Parameter(Mandatory, ValueFromPipelineByPropertyName, ParameterSetName = 'FromTitle', Position=0)]
    [ValidateNotNullOrEmpty()]
    [string]$FromTitle,

    [Parameter(Mandatory, ValueFromPipelineByPropertyName, ParameterSetName = 'PageID', Position=0)]
    [Alias('PageID')]
    [uint32]$ID,

    [Parameter(ValueFromPipelineByPropertyName)]
    [AllowEmptyString()]
    [string]$Summary,

    [Parameter()]
    [AllowEmptyString()]
    [Alias('Text', 'Wikitext')]
    [string]$Content,

    [switch]$NoNewline,

    <#
      Section based stuff
    #>
    [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
    [Alias('SectionIndex')]
    [uint32]$Index,

    <#
      Append / Prepend
    #>
    # Add this text to the end of the page or section. Overrides text.
    # Use section=new to append a new section, rather than this parameter. 
    #[Alias('AppendText')]
    #[switch]$Append, (default)

    # Add text before the section title.
    [Alias('PrependText')]
    [switch]$Prepend,

    <#
      Verification
    #>
    [Alias('BaseRevID')]
    [uint32]$BaseRevisionID,
    [string]$BaseTimestamp,
    [string]$StartTimestamp,

    <#
      Watchlist
    #>
    [Watchlist]$Watchlist = [Watchlist]::Preferences,

    <#
      Page related stuff
    #>
    [switch]$FollowRedirects, # Resolve redirects?

    <#
      Tags applied to the edit
    #>
    [switch]$Bot,
    [switch]$Minor,
    [switch]$Major,
    [string[]]$Tags, # Tag the edit according to one or more tags available in Special:Tags

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

    if ($FromTitle)
    { $Name = $FromTitle }

    if (-not $NoNewline -and -not [string]::IsNullOrWhiteSpace($Content))
    {
      if ($Prepend -and $Content -notmatch "\n$")
      { $Content = "$Content`n" }
      elseif ($Content -notmatch "^\n")
      { $Content = "`n$Content" }
    }

    $Parameters    = @{
      Section      = $true
      SectionIndex = $Index
      NoCreate     = $true
      JSON         = $JSON
    }

    if ($Name)
    { $Parameters.Name = $Name }

    if ($ID)
    { $Parameters.ID = $ID }

    if ($Summary)
    { $Parameters.Summary = $Summary }

    if ($Content)
    { $Parameters.Content = $Content }

    # Append/Prepend

    if ($Prepend)
    { $Parameters.Prepend = $Prepend }
    else
    { $Parameters.Append = $true }

    # Verification

    if ($BaseRevisionID)
    { $Parameters.BaseRevisionID = $BaseRevisionID }

    if ($BaseTimestamp)
    { $Parameters.BaseTimestamp = $BaseTimestamp }

    if ($StartTimestamp)
    { $Parameters.StartTimestamp = $StartTimestamp }

    # Watchlist

    if ($Watchlist)
    { $Parameters.Watchlist = $Watchlist }

    # Page stuff

    if ($FollowRedirects)
    { $Parameters.FollowRedirects = $FollowRedirects }

    # Edit tags

    if ($Bot)
    { $Parameters.Bot = $Bot }

    if ($Minor)
    { $Parameters.Minor = $Minor }

    if ($Major)
    { $Parameters.Major = $Major }

    if ($Tags)
    { $Parameters.Tags = $Tags }

    return Set-MWPage @Parameters
  }

  End { }
}
#endregion

#region Clear-MWPage
function Clear-MWPage
{
  <#
  .SYNOPSIS
    Clears the contents of the specified page.

  .DESCRIPTION
    The cmdlet is a front for Set-MWPage that makes it easier to clear a page.

  .PARAMETER Name
    Name of the page to edit. Cannot be used alongside the -ID parameter.

  .PARAMETER ID
    ID of the page to edit. Cannot be used alongside the -Name parameter.

  .PARAMETER Summary
    A short summary to attach to the edit.

  .PARAMETER BaseRevisionID
    ID of the base revision, used to detect edit conflicts.

  .PARAMETER BaseTimestamp
    Timestamp of the base revision, used to detect edit conflicts.

  .PARAMETER StartTimestamp
    Timestamp when the editing process began, used to detect edit conflicts.

  .PARAMETER Watchlist
    Defines whether to add the page to the user's watchlist or not.

  .PARAMETER FollowRedirects
    Switch to retrieve information about the target pages of any given redirect page, instead of the redirect page itself.

  .PARAMETER Bot
    Switch used to indicate the edit was performed by a bot.

  .PARAMETER Minor
    Switch used to indicate the edit is of a minor concern.

  .PARAMETER Minor
    Switch used to indicate the edit is of a major concern.

  .PARAMETER Tags
    Tag the edit according to one or more tags available in Special:Tags

  .INPUTS
    Name (System.String) of the page to clear. Cannot be used with -ID.
    
  .INPUTS
    ID (System.UInt32) of the page to clear. Cannot be used with -Name.

  .INPUTS
    Summary (System.String) of the edit summary.

  .OUTPUTS
    Returns a PSObject object containing the results of the edit.
  #>
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
    [Alias('PageID')]
    [uint32]$ID,

    [Parameter(ValueFromPipelineByPropertyName)]
    [AllowEmptyString()]
    [string]$Summary,

    <#
      Verification
    #>
    [Alias('BaseRevID')]
    [uint32]$BaseRevisionID,
    [string]$BaseTimestamp,
    [string]$StartTimestamp,

    <#
      Watchlist
    #>
    [Watchlist]$Watchlist = [Watchlist]::Preferences,

    <#
      Page related stuff
    #>
    [switch]$FollowRedirects, # Resolve redirects?

    <#
      Tags applied to the edit
    #>
    [switch]$Bot,
    [switch]$Minor,
    [switch]$Major,
    [string[]]$Tags, # Tag the edit according to one or more tags available in Special:Tags

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

    $Parameters    = @{
      Content      = ''
      NoCreate     = $true
      JSON         = $JSON
    }

    if ($Name)
    { $Parameters.Name = $Name }

    if ($ID)
    { $Parameters.ID = $ID }

    if ($Summary)
    { $Parameters.Summary = $Summary }

    # Verification

    if ($BaseRevisionID)
    { $Parameters.BaseRevisionID = $BaseRevisionID }

    if ($BaseTimestamp)
    { $Parameters.BaseTimestamp = $BaseTimestamp }

    if ($StartTimestamp)
    { $Parameters.StartTimestamp = $StartTimestamp }

    # Watchlist

    if ($Watchlist)
    { $Parameters.Watchlist = $Watchlist }

    # Page stuff

    if ($FollowRedirects)
    { $Parameters.FollowRedirects = $FollowRedirects }

    # Edit tags

    if ($Bot)
    { $Parameters.Bot = $Bot }

    if ($Minor)
    { $Parameters.Minor = $Minor }

    if ($Major)
    { $Parameters.Major = $Major }

    if ($Tags)
    { $Parameters.Tags = $Tags }

    return Set-MWPage @Parameters
  }

  End { }
}
#endregion

#region Clear-MWSection
function Clear-MWSection
{
  <#
  .SYNOPSIS
    Clears the contents of the specified section on the given page.

  .DESCRIPTION
    The cmdlet is a front for Set-MWPage that makes it easier to clear a specific section.

  .PARAMETER Name
    Name of the page to edit. Cannot be used alongside the -ID parameter.

  .PARAMETER FromTitle
    Alias for the -Name parameter.

  .PARAMETER ID
    ID of the page to edit. Cannot be used alongside the -Name parameter.

  .PARAMETER Summary
    A short summary to attach to the edit.

  .PARAMETER Index
    The section index to edit, retrieved through Get-MWPage.

  .PARAMETER BaseRevisionID
    ID of the base revision, used to detect edit conflicts.

  .PARAMETER BaseTimestamp
    Timestamp of the base revision, used to detect edit conflicts.

  .PARAMETER StartTimestamp
    Timestamp when the editing process began, used to detect edit conflicts.

  .PARAMETER Watchlist
    Defines whether to add the page to the user's watchlist or not.

  .PARAMETER FollowRedirects
    Switch to retrieve information about the target pages of any given redirect page, instead of the redirect page itself.

  .PARAMETER Bot
    Switch used to indicate the edit was performed by a bot.

  .PARAMETER Minor
    Switch used to indicate the edit is of a minor concern.

  .PARAMETER Minor
    Switch used to indicate the edit is of a major concern.

  .PARAMETER Tags
    Tag the edit according to one or more tags available in Special:Tags
    
  .INPUTS
    Name (System.String) of the page to edit. Cannot be used alongside the -ID parameter.
    
  .INPUTS
    FromTitle (System.String) as an alias for -Name.

  .INPUTS
    ID (System.UInt32) of the page to edit. Cannot be used alongside the -Name parameter.

  .INPUTS
    Summary (System.String) of the edit summary.

  .INPUTS
    Index (System.UInt32) of the section to edit.

  .OUTPUTS
    Returns a PSObject object containing the results of the edit.
  #>
  [CmdletBinding(DefaultParameterSetName = 'PageName')]
  param (
    <#
      Core parameters
    #>
    [Parameter(Mandatory, ValueFromPipelineByPropertyName, ParameterSetName = 'PageName', Position=0)]
    [ValidateNotNullOrEmpty()]
    [Alias('Title', 'Identity', 'PageName')]
    [string]$Name,

    # Alias for $Name, but in a way to support ValueFromPipelineByPropertyName
    [Parameter(Mandatory, ValueFromPipelineByPropertyName, ParameterSetName = 'FromTitle', Position=0)]
    [ValidateNotNullOrEmpty()]
    [string]$FromTitle,

    [Parameter(Mandatory, ValueFromPipelineByPropertyName, ParameterSetName = 'PageID', Position=0)]
    [Alias('PageID')]
    [uint32]$ID,

    [Parameter(ValueFromPipelineByPropertyName)]
    [AllowEmptyString()]
    [string]$Summary,

    <#
      Section based stuff
    #>
    [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
    [Alias('SectionIndex')]
    [uint32]$Index,

    <#
      Verification
    #>
    [Alias('BaseRevID')]
    [uint32]$BaseRevisionID,
    [string]$BaseTimestamp,
    [string]$StartTimestamp,

    <#
      Watchlist
    #>
    [Watchlist]$Watchlist = [Watchlist]::Preferences,

    <#
      Page related stuff
    #>
    [switch]$FollowRedirects, # Resolve redirects?

    <#
      Tags applied to the edit
    #>
    [switch]$Bot,
    [switch]$Minor,
    [switch]$Major,
    [string[]]$Tags, # Tag the edit according to one or more tags available in Special:Tags

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

    if ($FromTitle)
    { $Name = $FromTitle }

    $Current = @{
      Wikitext     = $true
      SectionIndex = $Index
    }

    if ($Name)
    { $Current.Name = $Name }
    
    if ($ID)
    { $Current.ID = $ID }

    $SectionContent = Get-MWSection @Current

    if ($null -eq $SectionContent)
    {
      Write-Warning 'Could not retrieve section content from the specified page!'
      return $null
    }

    # Clearing the section means retaining just the section header...
    # Header will always be the first line of the section content
    $NewContent = (($SectionContent.Wikitext) -split '\n')[0]

    $Parameters    = @{
      Section      = $true
      SectionIndex = $Index
      Content      = $NewContent
      NoCreate     = $true
      JSON         = $JSON
    }

    if ($Name)
    { $Parameters.Name = $Name }

    if ($ID)
    { $Parameters.ID = $ID }

    if ($Summary)
    { $Parameters.Summary = $Summary }

    # Verification

    if ($BaseRevisionID)
    { $Parameters.BaseRevisionID = $BaseRevisionID }

    if ($BaseTimestamp)
    { $Parameters.BaseTimestamp = $BaseTimestamp }

    if ($StartTimestamp)
    { $Parameters.StartTimestamp = $StartTimestamp }

    # Watchlist

    if ($Watchlist)
    { $Parameters.Watchlist = $Watchlist }

    # Page stuff

    if ($FollowRedirects)
    { $Parameters.FollowRedirects = $FollowRedirects }

    # Edit tags

    if ($Bot)
    { $Parameters.Bot = $Bot }

    if ($Minor)
    { $Parameters.Minor = $Minor }

    if ($Major)
    { $Parameters.Major = $Major }

    if ($Tags)
    { $Parameters.Tags = $Tags }

    return Set-MWPage @Parameters
  }

  End { }
}
#endregion

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

    if ($null -ne $script:MWTokens)
    { Clear-Variable MWTokens -Scope Script }

    if ($null -ne $script:Config)
    { Clear-Variable Config -Scope Script }

    if ($null -ne $script:Cache)
    { Clear-Variable Cache -Scope Script }

    # Reset the variables to their default values
    $global:MWSession      = $null
    
    $script:MWSessionGuest = $false
    $script:MWSessionBot   = $false

    $script:MWTokens       = @{
      CreateAccount        = $null
      CSRF                 = $null
      Patrol               = $null
      Rollback             = $null
      UserRights           = $null
      Watch                = $null
    }

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
    <#
      Main parameters
    #>
    [switch]$Persistent,
    [switch]$Guest,
    [switch]$Reset,

    <#
      Optional parameters
    #>
    [string]$ApiEndpoint,
    [switch]$Silent
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

        # Set to force an anonymous session
        if (-not $Guest)
        {
          # Try to convert the hashed password. This will only work on the same machine that the config file was created on.
          $TempConfig.Password = ConvertTo-SecureString $TempConfig.Password -ErrorAction Stop
        } else {
          $TempConfig.Username = $null 
          $TempConfig.Password = $null
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
      if ([string]::IsNullOrWhiteSpace($ApiEndpoint) -and -not ($ApiEndpoint = Read-Host 'Type in the full URI to the API endpoint [https://www.pcgamingwiki.com/w/api.php]'))
      { $ApiEndpoint = 'https://www.pcgamingwiki.com/w/api.php' }
      $Split    = ($ApiEndpoint -split '://')
      $Split2   = ($Split[1] -split '/')
      $Protocol = $Split[0] + '://'
      $API      = $Split2[-1]
      $Wiki     = $ApiEndpoint -replace $Protocol, '' -replace $API, ''

      if (-not $Guest)
      {
        $Username = Read-Host 'Username'
        [SecureString]$SecurePassword = Read-Host 'Password' -AsSecureString
      }

      $TempConfig = @{
        Protocol  = $Protocol
        Wiki      = $Wiki
        API       = $API
        Username  = $Username
        Password  = if ($SecurePassword.Length -eq 0) { $null } else { $SecurePassword | ConvertFrom-SecureString }
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

        $Response = Invoke-MWApiRequest -Body $Body -Method POST -IgnoreDisconnect -NoAssert -WebSession $global:MWSession

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
    $script:Cache.UserInfo = Get-MWCurrentUser

    # Cache change tags
    Get-MWChangeTag | Out-Null

    if (-not $Silent)
    {
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
    }

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

      if ($Properties -notcontains 'wikitext')
      { $Properties += @('wikitext') }

      if ($Properties -notcontains 'text')
      { $Properties += @('text') }

      $Body.prop = ($Properties.ToLower() -join '|')
    }

    $ArrJSON += Invoke-MWApiRequest -Body $Body -Method POST
  }

  End
  {
    if ($JSON)
    { return $ArrJSON }

    if ($PSCustomObject = $ArrJSON.parse | ForEach-Object { ConvertFrom-HashtableToPSObject $_ })
    {
      # Irrelevant and confusing, as it points to the "API" page for some random reason
      $PSCustomObject.PSObject.Properties.Remove('Name')
      $PSCustomObject.PSObject.Properties.Remove('ID')

      return $PSCustomObject
    }
  }
}
#endregion

#region Disconnect-MWSession
Set-Alias -Name Remove-MWSession -Value Disconnect-MWSession
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
    }

    # An edit token is required to sign out?!
    $Response = Invoke-MWApiRequest -Body $Body -Method POST -Token CSRF -IgnoreDisconnect -NoAssert

    Clear-MWSession

    if ($JSON)
    { return $Response }

    return $null
  }
}
#endregion

#region Find-MWFile
function Find-MWFile
{
  [CmdletBinding(DefaultParameterSetName='BetweenNames')]
  param
  (
    <#
      Search by name
    #>
    [Parameter(ParameterSetName = 'BetweenNames', Position=0)]
    [Alias('ImageName', 'FileName', 'Prefix')]
    [string]$Name,

    [Parameter(ParameterSetName = 'BetweenNames')]
    [string]$From,

    [Parameter(ParameterSetName = 'BetweenNames')]
    [string]$To,

    <#
      Search by timestamp
    #>
    [Parameter(ParameterSetName = 'BetweenTimestamp')]
    [Parameter(ParameterSetName = 'BetweenTimestampUser')]
    [Parameter(ParameterSetName = 'BetweenTimestampFilter')]
    [string]$Start,

    [Parameter(ParameterSetName = 'BetweenTimestamp')]
    [Parameter(ParameterSetName = 'BetweenTimestampUser')]
    [Parameter(ParameterSetName = 'BetweenTimestampFilter')]
    [string]$End,

    [Parameter(Mandatory, ParameterSetName = 'BetweenTimestampUser')]
    [string]$User,

    [Parameter(Mandatory, ParameterSetName = 'BetweenTimestampFilter')]
    [ValidateSet('All', 'Bots', 'NoBots')]
    [string]$Filter,

    <#
      Search direction
    #>
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

    $SortProperty = 'name'

    if ($PSCmdlet.ParameterSetName -like "BetweenTimestamp*")
    { $SortProperty = 'timestamp' }

    # Preparation
    $Body = [ordered]@{
      action        = 'query'
      list          = 'allimages'
      ailimit       = 'max'
      aisort        = $SortProperty
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

    # BetweenNames
    if ($PSCmdlet.ParameterSetName -eq 'BetweenNames')
    {
      if (-not [string]::IsNullOrWhiteSpace($Name))
      { $Body.aiprefix = $Name }

      if (-not [string]::IsNullOrWhiteSpace($From))
      { $Body.aifrom   = $From }

      if (-not [string]::IsNullOrWhiteSpace($To))
      { $Body.aito     = $To }
    }

    # BetweenTimestamp*
    if ($PSCmdlet.ParameterSetName -like "BetweenTimestamp*")
    {
      if (-not [string]::IsNullOrWhiteSpace($Start))
      {
        if ($Start -eq 'now')
        { $Start = (Get-Date) }
        else
        { $Start = [DateTime]$Start }
        
        $Body.aistart = (Get-Date ($Start).ToUniversalTime() -UFormat '+%Y-%m-%dT%H:%M:%SZ')
      }

      if (-not [string]::IsNullOrWhiteSpace($End))
      {
        if ($End -eq 'now')
        { $End = (Get-Date) }
        else
        { $End = [DateTime]$End }

        $Body.aiend = (Get-Date ($End).ToUniversalTime() -UFormat '+%Y-%m-%dT%H:%M:%SZ')
      }

      # BetweenTimestampUser
      if (-not [string]::IsNullOrWhiteSpace($User))
      { $Body.aiuser       = $User }
      # BetweenTimestampFilter
      if (-not [string]::IsNullOrWhiteSpace($Filter))
      { $Body.aifilterbots = $Filter.ToLower() }
    }

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

#region Find-MWFileDuplicate
function Find-MWFileDuplicate
{
  [CmdletBinding(DefaultParameterSetName = 'PageName')]
  param (
    <#
      Core parameters
    #>
    [Parameter(Mandatory, ValueFromPipelineByPropertyName, ParameterSetName = 'PageName', Position=0)]
    [ValidateNotNullOrEmpty()]
    [Alias('ImageName', 'FileName')]
    [string[]]$Name,

    [Parameter(Mandatory, ValueFromPipelineByPropertyName, ParameterSetName = 'PageID', Position=0)]
    [Alias('PageID')]
    [int[]]$ID,

    [ValidateScript({ Test-MWResultSize -InputObject $PSItem })]
    [string]$ResultSize = 1000,

    [Parameter(ParameterSetName = 'All')]
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
    {
      $FixedNames = @()
      ForEach ($FileName in $Name)
      {
        if ((Get-MWNamespace -PageName $FileName).Name -ne 'File')
        { $FixedNames += "File:$FileName" }
        else
        { $FixedNames += $FileName }
      }
      $Body.titles = $FixedNames -join '|'
    }

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

#region Find-MWPage
# Not to be mistaken for Search-MWPage!
function Find-MWPage
{
  [CmdletBinding(DefaultParameterSetName = 'None')]
  param
  (
    [Parameter(ValueFromPipelineByPropertyName, Position=0)]
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
    
    [Parameter(Mandatory, ParameterSetName='ByProtection')]
    [ValidateScript({ Test-MWProtectionType -InputObject $PSItem })]
    [string[]]$ProtectionType,

    # ()
    [Parameter(Mandatory, ParameterSetName='ByProtection')]
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

#region Find-MWRedirectOrphan
# Finds all redirect pages which no other pages link to.
function Find-MWRedirectOrphan
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
      $Links = Get-MWBackLink -ID $Page.ID -ResultSize Unlimited
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

#region Get-MWAPIModule
function Get-MWAPIModule
{
  <#
  .SYNOPSIS
    Retrieves information about API modules available on the site.

  .PARAMETER Properties
    List of module names (values of the action and format parameters, or main). Can specify submodules with a +, or all submodules with +*, or all submodules recursively with +**. 

  .PARAMETER HelpFormat
    How to format the help parts of the response, mostly the Description and Examples. Defaults to 'None'.

  .INPUTS
    None.

  .OUTPUTS
    Array of PSObject holding the information about the requested API modules.
  #>
  [CmdletBinding()]
  param (
    # [action|format][+submodule], assumes 'main' if no action or format is specified.
    # e.g. 'query+*' to retrieve info about all submodules to the 'query' action
    # 'main+**' retrieve info about all submodules of all actions.
    [string[]]$Properties,

    [ValidateSet('None', 'Wikitext', 'Html', 'Raw')]
    [string]$HelpFormat = 'None',

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

    $Body = [ordered]@{
      action     = 'paraminfo'
      modules    = $Properties -join '|'
      helpformat = $HelpFormat.ToLower()
    }

    $Response = Invoke-MWApiRequest -Body $Body -Method POST -IgnoreDisconnect -NoAssert

    if ($JSON)
    { return $Response }

    return ($Response.paraminfo.modules | ForEach-Object { ConvertFrom-HashtableToPSObject $_ })
  }
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
    [Parameter(Mandatory, ValueFromPipelineByPropertyName, ParameterSetName = 'PageName', Position=0)]
    [ValidateNotNullOrEmpty()]
    [Alias('Title', 'Identity', 'PageName')]
    [string]$Name,

    [Parameter(Mandatory, ValueFromPipelineByPropertyName, ParameterSetName = 'PageID', Position=0)]
    [Alias('PageID')]
    [uint32]$ID,

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
    [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
    #[Alias('Table')]
    [string[]]$Tables, # The Cargo database table or tables on which to search

    [Parameter(ValueFromPipelineByPropertyName)]
    #[Alias('Field')]
    [AllowEmptyString()]
    [string[]]$Fields = '', # The table field(s) to retrieve

    [Parameter(ValueFromPipelineByPropertyName)]
    [string]$Where, # The conditions for the query, corresponding to an SQL WHERE clause

    [Parameter(ValueFromPipelineByPropertyName)]
    [string]$JoinOn, # Conditions for joining multiple tables, corresponding to an SQL JOIN ON clause

    [Parameter(ValueFromPipelineByPropertyName)]
    [string]$GroupBy, # Field(s) on which to group results, corresponding to an SQL GROUP BY clause

    [Parameter(ValueFromPipelineByPropertyName)]
    [string]$Having, # Conditions for grouped values, corresponding to an SQL HAVING clause

    [Parameter(ValueFromPipelineByPropertyName)]
    [string]$OrderBy, # The order of results, corresponding to an SQL ORDER BY clause

    [Parameter(ValueFromPipelineByPropertyName)]
    [uint32]$Offset, # The query offset. The value must be no less than 0.

    [Parameter(ValueFromPipelineByPropertyName)]
    [Alias('ResultSize')]
    [ValidateScript({ Test-MWResultSize -InputObject $PSItem })]
    [string]$Limit = 1000, # A limit on the number of results returned, corresponding to an SQL LIMIT clause
    
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
      action = 'cargoquery'
      tables = $Tables -join ','
      fields = ($Tables[0] + '._pageName=Name,' + $Tables[0] + '._pageID=ID,' + $Tables[0] + '._pageNamespace=NamespaceID')
      limit  = 'max'
    }

    if ($Limit -eq 'Unlimited')
    { $Limit = [int32]::MaxValue } # int32 because of Select-Object -First [int32]

    #if ($Limit -ne 0)
    #{ $Body.limit = $Limit }

    if (-not [string]::IsNullOrWhiteSpace($Fields))
    { $Body.fields = ($Body.fields + ',' + ($Fields -join ',')) }

    if (-not [string]::IsNullOrWhiteSpace($Where))
    { $Body.where = $Where }

    if (-not [string]::IsNullOrWhiteSpace($JoinOn))
    { $Body.join_on = $JoinOn }

    if (-not [string]::IsNullOrWhiteSpace($GroupBy))
    { $Body.group_by = $GroupBy }

    if (-not [string]::IsNullOrWhiteSpace($Having))
    { $Body.having = $Having }

    if (-not [string]::IsNullOrWhiteSpace($OrderBy))
    { $Body.order_by = $OrderBy }

    if (-not [string]::IsNullOrWhiteSpace($Offset))
    { $Body.offset = $Offset }

    $Response = $null
    do
    {
      $Response = Invoke-MWApiRequest -Body $Body -Method GET
      $ArrJSON += $Response

      if ($ArrJSON.cargoquery.title.Count -ge $Limit)
      {
        $MoreAvailable = ($null -ne $Response.cargoquery -and $Response.cargoquery.Count -eq $Response.limits.cargoquery)
        Write-MWWarningResultSize -InputObject $MoreAvailable -DefaultSize 1000 -ResultSize $Limit
        break
      }

      $Body.offset = $Body.offset + $Response.limits.cargoquery
    } while ($null -ne $Response.cargoquery -and $Response.cargoquery.Count -eq $Response.limits.cargoquery)
  }

  End
  {
    if ($JSON)
    { return $ArrJSON }

    return (($ArrJSON.cargoquery.title | Select-Object -First $Limit) | ForEach-Object { ConvertFrom-HashtableToPSObject $_ })
  }
}
#endregion

#region Get-MWCategoryMember
function Get-MWCategoryMember
{
  [CmdletBinding(DefaultParameterSetName = 'CategoryName')]
  param (
    [Parameter(Mandatory, ValueFromPipelineByPropertyName, ParameterSetName = 'CategoryName', Position=0)]
    [Alias('Category', 'Identity', 'Group')]
    [string]$Name,

    [Parameter(Mandatory, ValueFromPipelineByPropertyName, ParameterSetName = 'CategoryID', Position=0)]
    [Alias('CategoryID')]
    [uint32]$ID,

    [ValidateScript({ Test-MWNamespace -InputObject $PSItem -AllowWildcard })]
    [string[]]$Namespace,

    [ValidateSet('', '*', 'IDs', 'SortKey', 'SortKeyPrefix', 'Timestamp', 'Title', 'Type')]
    [string[]]$Properties = @('IDs', 'Title'),

    [ValidateSet('*', 'Page', 'SubCat', 'File')]
    [string[]]$Type = @('Page', 'SubCat', 'File'),

    [ValidateSet('SortKey', 'Timestamp')]
    [string]$SortProperty = 'SortKey',

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

#region Get-MWChangeTag
function Get-MWChangeTag
{
  <#
  .SYNOPSIS
    Retrieves the recognized change tags of the site.

  .DESCRIPTION
    Retrieves the specified properties about the change tags of the site.

  .PARAMETER Properties
    String array of properties to retrieve for the change tags. Use * to retrieve all properties.

  .PARAMETER ManualOnly
    Switch used to indicate that only manual change tags should be returned.

  .INPUTS
    None.

  .OUTPUTS
    Array of PSObject holding the requested properties of the change tags.
  #>
  [CmdletBinding(DefaultParameterSetName = 'UserName')]
  param
  (
    <#
      Core parameters
    #>
    
    [Parameter()]
    [ValidateSet('', '*', 'active', 'defined', 'description', 'displayname', 'hitcount', 'source')]
    [string[]]$Properties = @('active', 'description', 'displayname', 'source'),

    [switch]$Active,
    [switch]$Manual,

    [ValidateScript({ Test-MWResultSize -InputObject $PSItem })]
    [string]$ResultSize = 1000,
    
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

    if ($ResultSize -eq 'Unlimited')
    { $ResultSize = [int32]::MaxValue } # int32 because of Select-Object -First [int32]

    $Body = [ordered]@{
      action  = 'query'
      list    = 'tags'
      tglimit = 'max'
    }

    if ($Properties -contains '*')
    { $Properties = @('active', 'defined', 'description', 'displayname', 'hitcount', 'source') }

    if ($Properties)
    { $Body.tgprop = ($Properties.ToLower() -join '|') }

    $Response = Invoke-MWApiContinueRequest -Body $Body -Method GET -ResultSize $ResultSize -Node1 'tags'

    $PSCustomObject = ($Response.query.tags | Select-Object -First $ResultSize | ForEach-Object { ConvertFrom-HashtableToPSObject $_ })

    # Update the local cache
    if ($null -ne $PSCustomObject )
    { $script:Cache.ChangeTag = ($PSCustomObject | Where-Object { $_.Source -eq 'manual' -and $_.Active -eq $true }).Name }

    if ($JSON)
    { return $Response }

    if ($Active)
    { $PSCustomObject = ($PSCustomObject | Where-Object { $_.Active -eq $true }) }

    if ($Manual)
    { $PSCustomObject = ($PSCustomObject | Where-Object { $_.Source -eq 'manual' }) }

    return $PSCustomObject
  }
}
#endregion

#region Get-MWCurrentUser
function Get-MWCurrentUser
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

    $Response = Invoke-MWApiRequest -Body $Body -Method GET -IgnoreDisconnect

    if ($JSON)
    { return $Response }

    $PSCustomObject = $Response.query.userinfo | ForEach-Object { ConvertFrom-HashtableToPSObject $_ }

    return $PSCustomObject
  }
}
#endregion

#region Get-MWCurrentUserPreference
function Get-MWCurrentUserPreference
{
  [CmdletBinding()]
  param   ( )
  Begin   { }
  Process { }
  End     { return (Get-MWCurrentUser -Properties 'options').Options }
}
#endregion

#region Get-MWCurrentUserGroup
function Get-MWCurrentUserGroup
{
  [CmdletBinding()]
  param   ( )
  Begin   { }
  Process { }
  End     { return (Get-MWCurrentUser -Properties 'groups').Groups }
}
#endregion

#region Get-MWCurrentUserRateLimit
function Get-MWCurrentUserRateLimit
{
  [CmdletBinding()]
  param   ( )
  Begin   { }
  Process { }
  End     { return (Get-MWCurrentUser -Properties 'ratelimits').RateLimits }
}
#endregion

#region Get-MWCurrentUserRight
function Get-MWCurrentUserRight
{
  [CmdletBinding()]
  param   ( )
  Begin   { }
  Process { }
  End     { return (Get-MWCurrentUser -Properties 'rights').Rights }
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
    [Parameter(Mandatory, ValueFromPipelineByPropertyName, ParameterSetName = 'PageName', Position=0)]
    [ValidateNotNullOrEmpty()]
    [Alias('Title', 'Identity', 'PageName')]
    [string]$Name,

    [Parameter(Mandatory, ValueFromPipelineByPropertyName, ParameterSetName = 'PageID', Position=0)]
    [Alias('PageID')]
    [uint32]$ID,

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
  }
}
#endregion

#region Get-MWEventLog
# https://www.mediawiki.org/wiki/API:Logevents
# Very useful for bots!
function Get-MWEventLog
{
  [CmdletBinding()]
  param (
    # Comma-separated list of additional properties to include: comment, details, ids, parsedcomment, tags, timestamp, title, type, user, userid
    [ValidateSet('*', 'Comment', 'Details', 'IDs', 'ParsedComment', 'Tags', 'Timestamp', 'Title', 'Type', 'User', 'UserID')]
    [string[]]$Properties =  @('IDs', 'Title', 'Type', 'User', 'Timestamp', 'Comment', 'Details'),

    # Based on PCGW right now; should be dynamic.
    [ValidateSet('Block', 'Cargo', 'ContentModel', 'Create', 'Delete', 'Import', 'InterWiki', 'ManageTags', 'Merge', 'Move', 'NewUsers', 'Patrol', 'Protect', 'RenameUser', 'Rights', 'SpamBlacklist', 'Suppress', 'Tag', 'Thanks', 'Upload', 'UserMerge')]
    [string]$Type         = $null, # Filter log entries to only the specified type.

    # Should use ValidateSet as well; should be dynamic.
    [string]$Action       = $null, # Filter log actions to only this action. Overrides -Type.
    
    <#
      Sorting
    #>
    [string]$Start        = $null, # Timestamp to start enumerating from
    [string]$End          = $null, # Timestamp to stop enumerating from

    [switch]$Ascending,            # newer; List oldest first
    [switch]$Descending,           # older; List newest first (default)

    <#
      Filtering
    #>
    [string[]]$LogID,              # Filter entries to those matching the given log ID(s).
    [string]$User,                 # Filter entries to those made by the given user.
    [string]$PageName,             # Filter entries to those related to a page.
    [ValidateScript({ Test-MWNamespace -InputObject $PSItem -AllowWildcard })]
    [string[]]$Namespace,          # Filter to those in the given namespace.
    [string]$Tag,                  # Only list event entries tagged with this tag.

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
      action        = 'query'
      list          = 'logevents'
      lelimit       = 'max'
      ledir         = 'older'
    }

    if (-not [string]::IsNullOrEmpty($Properties))
    {
      # Convert everything to lowercase
      $Properties = $Properties.ToLower()

      # Does it include a wildcard?
      if ($Properties -contains '*')
      { $Properties = @('comment', 'details', 'ids', 'parsedcomment', 'tags', 'timestamp', 'title', 'type', 'user', 'userid') }
    }

    if (-not [string]::IsNullOrEmpty($Properties))
    { $Body.leprop = ($Properties -join '|') }

    # Action > Type
    if (-not [string]::IsNullOrEmpty($Action))
    { $Body.leaction = $Action.ToLower() }
    elseif (-not [string]::IsNullOrEmpty($Type))
    { $Body.letype   = $Type.ToLower() }

    if (-not [string]::IsNullOrWhiteSpace($Start))
    {
      $StartTime = $null
      if ($Start -eq 'now')
      {
        $StartTime = (Get-Date)
      } else {
        $StartTime = [DateTime]$Start
      }
      $Body.lestart = (Get-Date ($StartTime).ToUniversalTime() -UFormat '+%Y-%m-%dT%H:%M:%SZ')
    }

    if (-not [string]::IsNullOrWhiteSpace($End))
    {
      $EndTime = $null
      if ($End -eq 'now')
      {
        $EndTime = (Get-Date)
      } else {
        $EndTime = [DateTime]$End
      }
      $Body.leend = (Get-Date ($EndTime).ToUniversalTime() -UFormat '+%Y-%m-%dT%H:%M:%SZ')
    }

    if ($Ascending)
    { $Body.ledir = 'newer' }
    elseif ($Descending)
    { $Body.ledir = 'older' }

    if (-not [string]::IsNullOrEmpty($LogID))
    { $Body.leids = ($LogID -join '|') }

    if (-not [string]::IsNullOrEmpty($User))
    { $Body.leuser = $User }

    if (-not [string]::IsNullOrEmpty($PageName))
    { $Body.letitle = $PageName }

    $_Namespace = ConvertTo-MWNamespaceID $Namespace

    if (-not [string]::IsNullOrEmpty($_Namespace))
    { $Body.lenamespace = $_Namespace }

    if (-not [string]::IsNullOrEmpty($Tag))
    { $Body.letag = $Tag }

    $ArrJSON += Invoke-MWApiContinueRequest -Body $Body -Method GET -ResultSize $ResultSize -Node1 'logevents'
  }

  End {
    if ($JSON)
    { return $ArrJSON }

    $ArrPSCustomObject = @()
    if ($Events = $ArrJSON.query.logevents | Select-Object -First $ResultSize)
    {
      ForEach ($Event in $Events)
      {
        $ObjectProperties = [ordered]@{}

        # LogID
        if ($null -ne $Event.logid)
        { $ObjectProperties.LogID = $Event.logid }

        # Page Name (default; title)
        if ($null -ne $Event.title)
        { $ObjectProperties.Name = $Event.title }

        # Page ID (default; pageid)
        if ($null -ne $Event.pageid)
        { $ObjectProperties.ID = $Event.pageid }

        # Namespace (default; ns)
        if ($null -ne $Event.ns)
        { $ObjectProperties.Namespace = (Get-MWNamespace -NamespaceID $Event.ns).Name }

        # Log Page (default; logpage)
        if ($null -ne $Event.logpage)
        { $ObjectProperties.LogPageID = $Event.logpage }

        # Revision ID (default; revid)
        if ($null -ne $Event.revid)
        { $ObjectProperties.RevisionID = $Event.revid }

        # Params (???)
        if ($null -ne $Event.params)
        { $ObjectProperties.Parameters = $Event.params }

        # Type
        if ($null -ne $Event.type)
        { $ObjectProperties.Type = $Event.type }

        # Action
        if ($null -ne $Event.action)
        { $ObjectProperties.Action = $Event.action }

        # User (user)
        if ($null -ne $Event.user)
        { $ObjectProperties.User = $Event.user }

        # User ID (userid)
        if ($null -ne $Event.userid)
        { $ObjectProperties.UserID = $Event.userid }

        # Temp (???)
        if ($null -ne $Event.temp)
        { $ObjectProperties.TemporaryUser = $true } # Temporary User?

        # Timestamp (default; timestamp)
        if ($null -ne $Event.timestamp)
        { $ObjectProperties.Timestamp = $Event.timestamp }

        # Comment (comment)
        if ($null -ne $Event.comment)
        { $ObjectProperties.Comment = $Event.comment }

        # Parsed comment (parsedcomment)
        if ($null -ne $Event.parsedcomment)
        { $ObjectProperties.ParsedComment = $Event.parsedcomment }

        # Tags (tags), e.g. 'mw-blank' indicates a blanking change. See Special:Tags for a full list.
        if ($null -ne $Event.tags)
        { $ObjectProperties.Tags = $Event.tags }

        $ArrPSCustomObject += New-Object PSObject -Property $ObjectProperties
      }
    }
    return $ArrPSCustomObject
  }
}
#endregion

#region Get-MWFileInfo
function Get-MWFileInfo
{
  [CmdletBinding(DefaultParameterSetName = 'PageName')]
  param (
    <#
      Core parameters
    #>
    [Parameter(Mandatory, ValueFromPipelineByPropertyName, ParameterSetName = 'PageName', Position=0)]
    [ValidateNotNullOrEmpty()]
    [Alias('ImageName', 'FileName')]
    [string[]]$Name,

    [Parameter(Mandatory, ValueFromPipelineByPropertyName, ParameterSetName = 'PageID', Position=0)]
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
    {
      $FixedNames = @()
      ForEach ($FileName in $Name)
      {
        if ((Get-MWNamespace -PageName $FileName).Name -ne 'File')
        { $FixedNames += "File:$FileName" }
        else
        { $FixedNames += $FileName }
      }
      $Body.titles = $FixedNames -join '|'
    }

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

#region Get-MWFileUsage
function Get-MWFileUsage
{
  [CmdletBinding(DefaultParameterSetName = 'PageName')]
  param (
    <#
      Core parameters
    #>
    [Parameter(Mandatory, ValueFromPipelineByPropertyName, ParameterSetName = 'PageName', Position=0)]
    [ValidateNotNullOrEmpty()]
    [Alias('ImageName', 'FileName')]
    [string[]]$Name,

    [Parameter(Mandatory, ValueFromPipelineByPropertyName, ParameterSetName = 'PageID', Position=0)]
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
    {
      $FixedNames = @()
      ForEach ($FileName in $Name)
      {
        if ((Get-MWNamespace -PageName $FileName).Name -ne 'File')
        { $FixedNames += "File:$FileName" }
        else
        { $FixedNames += $FileName }
      }
      $Body.iutitle = $FixedNames -join '|'
    }

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

    $Body = [ordered]@{
      action        = 'query'
      list          = 'recentchanges'
     #rcprop        = 'info'
      rclimit       = 'max'
      rcdir         = 'older'
    }

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

    # TODO Convert to PSObject?

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

#region Get-MWNamespace
function Get-MWNamespace
{
  <#
  .SYNOPSIS
    Retrieves the namespaces of the site.

  .DESCRIPTION
    Retrieves the registered "positive" namespaces of the site, and can optionally include the "negative" special namespaces.

  .PARAMETER NamespaceName
    Name of the namespace to retrieve. Cannot be used alongside the -ID parameter.

  .PARAMETER NamespaceID
    ID of the namespace to retrieve. Cannot be used alongside the -Name parameter.

  .PARAMETER All
    Returns all registered namespaces.

  .PARAMETER IncludeNegative
    Switch used to indicate that any negative special namespaces should be included.

  .PARAMETER PageName
    Extracts and returns the details of a namespace from a given page name.
    
  .INPUTS
    NamespaceName (System.String) of the namespace to retrieve. Cannot be used alongside the -NamespaceID parameter.

  .INPUTS
    NamespaceID (System.Int32) of the namespace to retrieve. Cannot be used alongside the -NamespaceName parameter.

  .OUTPUTS
    Array of PSObject holding the generic information about the given namespaces.
  #>
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
    
    # The function can also alternative extract the namespace from a given (full) page name
    [Parameter(ParameterSetName = 'PageName', Position=0)]
    [AllowEmptyString()] # Main namespace has no name
    [string]$PageName,
    
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

    # Alternate mode
    if ($PageName)
    {
      $NamespacePortion = ''
      # First portion includes the namespace
      if ($PageName -like "*:*")
      { $NamespacePortion = ($PageName -split ':')[0] }
      # Recursive call for the win :)
      Get-MWNamespace -Name $NamespacePortion
    }

    # Main mode
    else
    {
      $NamespaceName = $NamespaceName.Replace(':', '')

      if ($null -ne $script:Cache.Namespace)
      {
        $LocalCopy = $null

        if ($IncludeNegative)
        { $LocalCopy = $script:Cache.Namespace }
        else 
        { $LocalCopy = $script:Cache.Namespace | Where-Object ID -ge 0 }

            if ($PSBoundParameters.ContainsKey('NamespaceName'))
        { return ($LocalCopy | Where-Object { $_.Name -eq $NamespaceName -or $_.Aliases -eq $NamespaceName } | Copy-Object) }
        elseif ($PSBoundParameters.ContainsKey('NamespaceID'))
        { return ($LocalCopy | Where-Object { $_.ID   -eq $NamespaceID } | Copy-Object) }
        else
        { return ($LocalCopy | Copy-Object) }
      }

      return $null
    }
  }

  End { }
}
#endregion

#region Get-MWNamespacePage
function Get-MWNamespacePage
{
  <#
  .SYNOPSIS
    Retrieve pages belonging to the given namespace.

  .PARAMETER Name
    Name of the namespace to retrieve pages from.

  .PARAMETER ResultSize
    Limit the returned results. Defaults to 1000.

  .INPUTS
    Name (System.String) of the namespace to retrieve pages for.

  .OUTPUTS
    Returns a PSObject array containing pages of the given namespace.
  #>
  [CmdletBinding()]
  param
  (
    [Parameter(Mandatory, ValueFromPipelineByPropertyName, Position=0)]
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
  <#
  .SYNOPSIS
    Retrieves a page.

  .DESCRIPTION
    Retrieves the contents of the given page and any specified properties.

  .PARAMETER Name
    Name of the page to retrieve. Cannot be used alongside the -ID parameter.

  .PARAMETER ID
    ID of the page to retrieve. Cannot be used alongside the -Name parameter.

  .PARAMETER Index
    Retrieve the contents of a single section using its index identifier, as retrieved through a regular Get-MWPage call.

  .PARAMETER Properties
    String array of properties to retrieve for the given page. Use * to retrieve all properties.

  .PARAMETER ParsedText
    Switch used to indicate the parsed HTML text of the page should be returned.

  .PARAMETER Wikitext
    Switch used to indicate the original wikitext of the page should be returned.

  .PARAMETER FollowRedirects
    Switch to retrieve information about the target pages of any given redirect page, instead of the redirect page itself.

  .PARAMETER Information
    Switch to retrieve additional information about the given page, using a subcall to Get-MWPageInfo.
    
  .INPUTS
    Name (System.String) of the page to retrieve. Cannot be used alongside the -ID parameter.

  .INPUTS
    ID (System.UInt32) of the page to retrieve. Cannot be used alongside the -Name parameter.

  .OUTPUTS
    PSObject holding the requested properties of the given page.
  #>
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
    [Alias('PageID')]
    [uint32]$ID,

    <#
      Section based stuff
    #>
    $SectionIndex,

    # MediaWiki Default: text|langlinks|categories|links|templates|images|externallinks|sections|revid|displaytitle|iwlinks|properties|parsewarnings
    [ValidateSet('', '*', 'Categories', 'CategoriesHtml', 'DisplayTitle', 'EncodedJSConfigVars', 'ExternalLinks', 'HeadHtml', 'Images', 'Indicators', 'IwLinks', 'JSConfigVars', 'LangLinks', 'LimitReportData', 'LimitReportHtml', 'Links', 'Modules', 'ParseTree', 'ParseWarnings', 'Properties', 'RevId', 'Sections', 'Templates', 'Text', 'Wikitext')]
    [string[]]$Properties = @('RevID', 'DisplayTitle', 'Categories', 'Templates', 'Images', 'ExternalLinks', 'Sections'),
    # Comma-separated list of additional properties to include:
    # categories, categorieshtml, displaytitle, encodedjsconfigvars, externallinks, headhtml, images, indicators, iwlinks, jsconfigvars, langlinks, limitreportdata, limitreporthtml, links, modules, parsetree, parsewarnings, parsewarningshtml, properties, revid, sections, subtitle, templates, text, wikitext
    # Deprecated: headitems
    # Unsupported on PCGW: ParseWarningsHtml, Subtitle

    [switch]$ParsedText,
    [switch]$Wikitext,

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

    if (-not [string]::IsNullOrEmpty($SectionIndex))
    { $Body.section = $SectionIndex }

    if (-not [string]::IsNullOrEmpty($Properties))
    {
      if ($Properties -contains '*')
      { $Properties = @('Categories', 'CategoriesHtml', 'DisplayTitle', 'EncodedJSConfigVars', 'ExternalLinks', 'HeadHtml', 'Images', 'Indicators', 'IwLinks', 'JSConfigVars', 'LangLinks', 'LimitReportData', 'LimitReportHtml', 'Links', 'Modules', 'ParseTree', 'ParseWarnings', 'Properties', 'RevId', 'Sections', 'Templates', 'Text', 'Wikitext') }

      if ($Wikitext -and $Properties -notcontains 'wikitext')
      { $Properties += @('wikitext') }

      if ($ParsedText -and $Properties -notcontains 'text')
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

    if ($PSCustomObject)
    {
      # Also attach the timestamp when the data was retrieved
      $PSCustomObject | Add-Member -MemberType NoteProperty -Name 'ServerTimestamp' -Value $ArrJSON.curtimestamp
    }

    return $PSCustomObject
  }
}
#endregion

#region Get-MWPageInfo
function Get-MWPageInfo
{
  <#
  .SYNOPSIS
    Retrieves information about the given pages.

  .PARAMETER Name
    String array of page names to retrieve information about. Cannot be used alongside the -ID parameter.

  .PARAMETER ID
    Integer array of page IDs to retrieve information about. Cannot be used alongside the -Name parameter.

  .PARAMETER FollowRedirects
    Switch to retrieve information about the target pages of any given redirect page, instead of the redirect page itself.
    
  .INPUTS
    Name (System.String) of the page to edit. Cannot be used alongside the -ID parameter.

  .INPUTS
    ID (System.UInt32) of the page to edit. Cannot be used alongside the -Name parameter.

  .OUTPUTS
    Returns a PSObject array containing information about the given pages.
  #>
  [CmdletBinding(DefaultParameterSetName = 'PageName')]
  param (
    <#
      Core parameters
    #>
    [Parameter(Mandatory, ValueFromPipelineByPropertyName, ParameterSetName = 'PageName', Position=0)]
    [ValidateNotNullOrEmpty()]
    [Alias('Title', 'Identity', 'PageName')]
    [string[]]$Name,

    [Parameter(Mandatory, ValueFromPipelineByPropertyName, ParameterSetName = 'PageID', Position=0)]
    [Alias('PageID')]
    [uint32[]]$ID,

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

    $ArrJSON += Invoke-MWApiRequest -Body $Body -Method GET
  }

  End
  {
    if ($JSON)
    { return $ArrJSON }
    
    return $ArrJSON.query.pages | ForEach-Object { ConvertFrom-HashtableToPSObject $_ }
  }
}
#endregion

#region Get-MWPageLink
#TODO: Generator. Evaluate?
function Get-MWPageLink
{
  [CmdletBinding()]
  param (
    <#
      Core parameters
    #>
    [Parameter(Mandatory, ValueFromPipelineByPropertyName, ParameterSetName = 'PageName', Position=0)]
    [ValidateNotNullOrEmpty()]
    [Alias('Title', 'Identity', 'PageName')]
    [string[]]$Name,

    [Parameter(Mandatory, ValueFromPipelineByPropertyName, ParameterSetName = 'PageID', Position=0)]
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

    return $ArrJSON.query.pages | Select-Object -First $ResultSize | ForEach-Object { ConvertFrom-HashtableToPSObject $_ }
  }
}
#endregion

#region Get-MWProtectionLevel
Set-Alias -Name Get-MWRestrictionLevel -Value Get-MWProtectionLevel
function Get-MWProtectionLevel
{
  <#
  .SYNOPSIS
    Retrieves protection level from the connected site.

  .ALIASES
    Get-MWRestrictionLevel

  .INPUTS
    None.

  .OUTPUTS
    Returns a string array of the protection levels of the site.
  #>
  return $script:Cache.RestrictionLevel
}
#endregion

#region Get-MWProtectionType
Set-Alias -Name Get-MWRestrictionType -Value Get-MWProtectionType
function Get-MWProtectionType
{
  <#
  .SYNOPSIS
    Retrieves protection types from the connected site.

  .ALIASES
    Get-MWRestrictionType

  .INPUTS
    None.

  .OUTPUTS
    Returns a string array of the protection types of the site.
  #>
  return $script:Cache.RestrictionType
}
#endregion

#region Get-MWSection
function Get-MWSection
{
  <#
  .SYNOPSIS
    Retrieves a section of the given page.

  .DESCRIPTION
    Retrieves the contents of the given page and any specified properties.

  .PARAMETER Name
    Name of the page to retrieve. Cannot be used alongside the -ID parameter.

  .PARAMETER FromTitle
    Alias for the -Name parameter.

  .PARAMETER ID
    ID of the page to retrieve. Cannot be used alongside the -Name parameter.

  .PARAMETER Index
    Identifier of the section to retrieve the contents of; index is retrieved through Get-MWPage.

  .PARAMETER Properties
    String array of properties to retrieve for the given page. Use * to retrieve all properties.

  .PARAMETER ParsedText
    Switch used to indicate the parsed HTML text of the page should be returned.

  .PARAMETER Wikitext
    Switch used to indicate the original wikitext of the page should be returned.

  .PARAMETER FollowRedirects
    Switch to retrieve information about the target pages of any given redirect page, instead of the redirect page itself.
    
  .INPUTS
    Name (System.String) of the page to retrieve the section from. Cannot be used alongside the -ID parameter.
    
  .INPUTS
    FromTitle (System.String) as an alias for -Name.

  .INPUTS
    ID (System.UInt32) of the page to retrieve the section from. Cannot be used alongside the -Name parameter.

  .INPUTS
    Index (System.UInt32) of the section to retrieve.

  .OUTPUTS
    PSObject holding the requested properties of the given page.
  #>
  [CmdletBinding(DefaultParameterSetName = 'PageName')]
  param (
    <#
      Core parameters
    #>
    [Parameter(Mandatory, ValueFromPipelineByPropertyName, ParameterSetName = 'PageName', Position=0)]
    [ValidateNotNullOrEmpty()]
    [Alias('Title', 'Identity', 'PageName')]
    [string]$Name,

    # Alias for $Name, but in a way to support ValueFromPipelineByPropertyName
    [Parameter(Mandatory, ValueFromPipelineByPropertyName, ParameterSetName = 'FromTitle', Position=0)]
    [ValidateNotNullOrEmpty()]
    [string]$FromTitle,

    [Parameter(Mandatory, ValueFromPipelineByPropertyName, ParameterSetName = 'PageID', Position=0)]
    [Alias('PageID')]
    [uint32]$ID,

    <#
      Section based stuff
    #>
    [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
    [Alias('SectionIndex')]
    [uint32]$Index,

    # Passthrough
    [string[]]$Properties,
    [switch]$ParsedText,
    [switch]$Wikitext,
    [switch]$FollowRedirects,

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

    if ($FromTitle)
    { $Name = $FromTitle }

    $Parameters       = @{
      SectionIndex    = $Index
      ParsedText      = $ParsedText
      Wikitext        = $Wikitext
      FollowRedirects = $FollowRedirects
      JSON            = $JSON
    }

    if ($ID)
    { $Parameters.ID = $ID }
    else
    { $Parameters.Name = $Name }

    if (-not [string]::IsNullOrEmpty($Properties))
    { $Parameters.Properties = $Properties }

    return Get-MWPage @Parameters
  }

  End { }
}
#endregion

#region Get-MWSession
function Get-MWSession
{
  <#
  .SYNOPSIS
    Retrieves data about the established MediaWiki API session.

  .INPUTS
    None.

  .OUTPUTS
    Returns the session variable for the active connection.
  #>
  [CmdletBinding()]
  param ( )

  Begin { }

  Process
  {
    if ($null -eq $global:MWSession)
    { Write-Verbose "There is no active MediaWiki session! Please use Connect-MWSession to sign in to a MediaWiki API endpoint." }

    return $global:MWSession
  }

  End { }
}
#endregion

#region Get-MWSiteInfo
function Get-MWSiteInfo
{
  <#
  .SYNOPSIS
    Retrieves properties about the connected site.

  .DESCRIPTION
    Retrieves the specified properties about the connected site.

  .PARAMETER Properties
    String array of properties to retrieve for the given users. Use * to retrieve all properties.

  .INPUTS
    None.

  .OUTPUTS
    PSObject holding the requested properties of the connected site.
  #>
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

    if ($Properties -contains 'namespaces' -and $Properties -notcontains 'namespacealiases')
    { $Properties += 'namespacealiases' }

    $Body = [ordered]@{
      action = 'query'
      meta   = 'siteinfo'
      siprop = ($Properties.ToLower() -join '|')
    }

    $Response = Invoke-MWApiRequest -Body $Body -Method GET -IgnoreDisconnect

    $PSCustomObject = $Response.query | ForEach-Object { ConvertFrom-HashtableToPSObject $_ }

    if ($null -ne $PSCustomObject.Restrictions)
    {
      # Clone the values for internal use
      $script:Cache.RestrictionType  =  $PSCustomObject.Restrictions.Types.Clone()
      $script:Cache.RestrictionLevel = ($PSCustomObject.Restrictions.Levels | Where-Object { $PSItem -ne '' }).Clone()
    }

    # Update the local namespace cache
    if ($null -ne $PSCustomObject.Namespaces)
    {
      $PSCustomObject.Namespaces = $PSCustomObject.Namespaces | ForEach-Object { ConvertFrom-HashtableToPSObject $_ }

      # Convert from object to array
      $ArrNamespaces = @()
      ForEach ($NamespaceProperty in $PSCustomObject.Namespaces.PSObject.Properties)
      {
        $Namespace      = $NamespaceProperty.Value
        $Namespace      = Rename-PropertyName $Namespace -PropertyName 'Content' -NewPropertyName 'IsContentNamespace'
        $ArrNamespaces += $Namespace
      }

      # Move namespace aliases into the Namespace array
      ForEach ($Namespace in $ArrNamespaces)
      { $Namespace | Add-Member -MemberType NoteProperty -Name 'Aliases' -Value (($PSCustomObject.NamespaceAliases | Where-Object { $_.ID -eq $Namespace.ID }).Alias) }
      $PSCustomObject.PSObject.Properties.Remove('NamespaceAliases')

      # Move it into the object we intend to return
      $PSCustomObject.Namespaces = $ArrNamespaces

      # Clone the values for internal use
      $script:Cache.Namespace = $ArrNamespaces.Clone()
    }

    if ($JSON)
    { return $Response }

    return $PSCustomObject
  }
}
#endregion

#region Get-MWToken
function Get-MWToken
{
  <#
  .SYNOPSIS
    Retrieves a token of the requested type.

  .PARAMETER Type
    Indicates which type of token to retrieve.

  .PARAMETER Force
    Ignore any cached token and retrieve a new one.

  .INPUTS
    None.

  .OUTPUTS
    The retrieved token as a string.
  #>
  [CmdletBinding()]
  param (
    [TokenType]$Type = [TokenType]::None,
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

    # Return all tokens if not specifying any
    if ($Type -eq [TokenType]::None)
    { return $script:MWTokens }

    $TypeAsString = $Type.ToString()

    if ($null -eq $script:MWTokens.$TypeAsString -or $Force)
    {
      $Body = [ordered]@{
        action = 'query'
        meta   = 'tokens'
        type   = $TypeAsString.ToLower()
      }

      $Response = Invoke-MWApiRequest -Body $Body -Method POST -IgnoreDisconnect -NoAssert

      if ($Response.query.tokens.createaccounttoken)
      { $script:MWTokens.$TypeAsString = $Response.query.tokens.createaccounttoken }

      if ($Response.query.tokens.csrftoken)
      { $script:MWTokens.$TypeAsString = $Response.query.tokens.csrftoken }

      if ($Response.query.tokens.patroltoken)
      { $script:MWTokens.$TypeAsString = $Response.query.tokens.patroltoken }

      if ($Response.query.tokens.rollbacktoken)
      { $script:MWTokens.$TypeAsString = $Response.query.tokens.rollbacktoken }

      if ($Response.query.tokens.userrightstoken)
      { $script:MWTokens.$TypeAsString = $Response.query.tokens.userrightstoken }

      if ($Response.query.tokens.watchtoken)
      { $script:MWTokens.$TypeAsString = $Response.query.tokens.watchtoken }

      if ($JSON)
      { return $Response }
    }

    return $script:MWTokens.$TypeAsString
  }
}
#endregion

#region Get-MWUnreadNotifications
<# Unread changes on the watchlist?
function Get-MWUnreadNotifications
{

  [CmdletBinding(DefaultParameterSetName = 'UserName')]
  param
  (
    # Group talk pages together with their subject page, and group notifications not associated with a page together with the current user's user page.
    [int]$GroupPages,

    [ValidateScript({ Test-MWResultSize -InputObject $PSItem })]
    [string]$ResultSize = 1000,
    
    [switch]$JSON
  )

  Begin
  {
    $ArrJSON = @()
  }

  Process { }

  End
  {
    if ($null -eq $script:Config.URI)
    {
      Write-Warning "Not connected to a MediaWiki instance."
      return $null
    }

    if ($ResultSize -eq 'Unlimited')
    { $ResultSize = [int32]::MaxValue }

    $Body = [ordered]@{
      action   = 'query'
      meta     = 'unreadnotificationpages'
      unplimit = 'max'
    }


    $ArrJSON += Invoke-MWApiContinueRequest -Body $Body -Method GET -ResultSize $ResultSize -Node1 'unreadnotificationpages'

    if ($JSON)
    { return $ArrJSON }

    $ArrPSCustomObject = @()
    ForEach ($Key in $ArrJSON.query.unreadnotificationpages.PSBase.Keys)
    {
      $Wiki       = $ArrJSON.query.unreadnotificationpages.$Key
      $Source     = $Wiki.source
      $TotalCount = $Wiki.totalCount # Wrong?
      if ($Pages = $Wiki.pages | Select-Object -First $ResultSize)
      {
        ForEach ($Page in $Pages)
        {
          $ObjectProperties = [ordered]@{
            Wiki  = $Source.title
            Page  = $Page.title
            Count = $Page.count
            Url   = $Source.base.Replace('$1', $Page.title.Replace(' ', '_'))
          }
          $ArrPSCustomObject += New-Object PSObject -Property $ObjectProperties
        }
      }
    }

    return $ArrPSCustomObject
  }
}
#>
#endregion

#region Get-MWUser
function Get-MWUser
{
  <#
  .SYNOPSIS
    Retrieves properties about the given users.

  .DESCRIPTION
    Retrieves the specified properties about the given usernames or user IDs.

  .PARAMETER Name
    String array of usernames to retrieve information about. Cannot be used alongside the -ID parameter.

  .PARAMETER ID
    Integer array of user IDs to retrieve information about. Cannot be used alongside the -Name parameter.

  .PARAMETER Properties
    String array of properties to retrieve for the given users. Use * to retrieve all properties.

  .PARAMETER AttachedWiki
    Integer to indicate a wiki ID to check whether the user is attached to.
    
  .INPUTS
    Name (System.String) of the page to retrieve the section from. Cannot be used alongside the -ID parameter.

  .INPUTS
    ID (System.UInt32) of the page to retrieve the section from. Cannot be used alongside the -Name parameter.

  .OUTPUTS
    Array of PSObject holding the requested properties of the given users.
  #>
  [CmdletBinding(DefaultParameterSetName = 'UserName')]
  param
  (
    <#
      Core parameters
    #>
    [Parameter(Mandatory, ValueFromPipelineByPropertyName, ParameterSetName = 'UserName', Position=0)]
    [ValidateNotNullOrEmpty()]
    [Alias('UserName')]
    [string[]]$Name,

    [Parameter(Mandatory, ValueFromPipelineByPropertyName, ParameterSetName = 'UserID', Position=0)]
    [Alias('UserID')]
    [int[]]$ID,

    # Use * to include all properties
    [Parameter()]
    [ValidateSet('', '*', 'blockinfo', 'cancreate', 'centralids', 'editcount', 'emailable', 'gender', 'groupmemberships', 'groups', 'implicitgroups', 'registration', 'rights')]
    [string[]]$Properties = @('editcount', 'groups', 'registration', 'rights'),
    # Not supported on PCGW?

    # With usprop=centralids, indicate whether the user is attached with the wiki identified by this ID. 
    [int]$AttachedWiki,
    
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

    $Body = [ordered]@{
      action = 'query'
      list   = 'users'
    }

    # With usprop=centralids, indicate whether the user is attached with the wiki identified by this ID. 
    if ($AttachedWiki)
    {
      if ($Properties -notcontains "centralids")
      { $Properties += 'centralids' }
      
      $Body.usattachedwiki = $AttachedWiki
    }

    if ($Properties -contains '*')
    { $Properties = @('blockinfo', 'cancreate', 'centralids', 'editcount', 'emailable', 'gender', 'groupmemberships', 'groups', 'implicitgroups', 'registration', 'rights') }

    if ($Name)
    { $Body.ususers = $Name -join '|' }

    if ($ID)
    { $Body.ususerids = $ID -join '|' }

    if ($Properties)
    { $Body.usprop = ($Properties.ToLower() -join '|') }

    $Response = Invoke-MWApiRequest -Body $Body -Method GET

    if ($JSON)
    { return $Response }

    return $Response.query.users | ForEach-Object { ConvertFrom-HashtableToPSObject $_ }
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

#region Import-MWFile
function Import-MWFile
{
  <#
  .SYNOPSIS
    Imports a file to MediaWiki.

  .DESCRIPTION
    Imports (uploads) a file (image) to the MediaWiki stite.

  .PARAMETER URL
    String of the URL the MediaWiki server should create a file from.

  .OUTPUTS
    Array of PSObject holding the requested properties of the given users.
  #>
  [CmdletBinding(DefaultParameterSetName = 'Url')]
  param
  (
    <#
      Core parameters
    #>
    [Parameter(Mandatory, ParameterSetName = 'File', Position=0)]
    [Parameter(Mandatory, ParameterSetName = 'Url', Position=0)]
    [ValidateNotNullOrEmpty()]
    [string]$Name,

    [Parameter(ValueFromPipelineByPropertyName)]
    [Alias('Text, Description')]
    [AllowEmptyString()]
    [string]$Comment, # Upload comment. Also used as the initial page text for new files if text is not specified. 

    <#
      Url based upload
    #>
    [Parameter(Mandatory, ParameterSetName = 'Url', Position=1)]
    [ValidateNotNullOrEmpty()]
    [string]$Url,

    <#
      File based upload
    #>
    # Note that the HTTP POST must be done as a file upload (i.e. using multipart/form-data) when sending the file or chunk.
    [Parameter(Mandatory, ParameterSetName = 'File', Position=1)]
    [ValidateNotNullOrEmpty()]
    [string]$File,

    [string]$FileKey,
    [switch]$Stash,

    <#
      Page stuff
    #>
    [ValidateScript({ Test-MWChangeTag -InputObject $PSItem })]
    [string[]]$Tags, # Tag the edit according to one or more tags available in Special:Tags

    [Watchlist]$Watchlist = [Watchlist]::Preferences,

    <#
      Switches
    #>
    [switch]$FixExtension, # Fix file MIME/extension mismatch automatically
    [switch]$Force,        # Ignore warnings
    
    <#
      Debug
    #>
    [switch]$JSON
  )

  Begin { }

  Process {
    if ($null -eq $script:Config.URI)
    {
      Write-Warning "Not connected to a MediaWiki instance."
      return $null
    }

    $Body = [ordered]@{
      action    = 'upload'
      filename  = $Name
      watchlist = $Watchlist.ToString().ToLower()
    }
    
    if ($Comment)
    { $Body.comment = $Comment }
    
    if ($Url)
    { $Body.url = $Url }
    
    if ($FileKey)
    { $Body.filekey = $FileKey }
    
    if ($Stash)
    { $Body.stash = $true } # omit outright to disable

    if ($Force)
    { $Body.ignorewarnings = $true } # omit outright to disable

    # Edit tags
    $JoinedTags     = ''

    if ($Tags)
    { $JoinedTags = $Tags -join '|' }

    if (-not [string]::IsNullOrEmpty($JoinedTags))
    { $Body.tags = $JoinedTags }

    $RequestParams = @{
      Body         = $Body
      Method       = 'POST'
      Token        = 'CSRF'
    }

    if ($File)
    {
      $RequestParams.ContentType = "multipart/form-data"
      $RequestParams.InFile      = $File
    }

    $Extensions = @{
     'image/jpeg'  = '.jpg'
     'image/png'   = '.png'
     'image/webp'  = '.webp'
    }

    $WarningMessages = @{
      'exists'            = 'A file with the given name already exists. If this warning is ignored, the uploaded file will replace the existing file. Use -Force to ignore this warning.'
      'nochange'          = 'A file with the given name already exists and is exactly the same as the uploaded file.'
      'no-change'         = 'A file with the given name already exists and is exactly the same as the uploaded file.'
      'duplicateversions' = 'A file with the given name already exists and an old version of that file is exactly the same as the uploaded file.'
      'badfilename'       = 'The file name supplied is not acceptable on this wiki, for instance because it contains forbidden characters.'
      'was-deleted'       = 'A file with the given name used to exist but has been deleted. Use -Force to ignore this warning.'
      'duplicate'         = 'The uploaded file exists under a different (or the same) name. Uploading a duplicate may be undesirable. Use -Force to ignore this warning.'
      'duplicate-archive' = 'The uploaded used to exist under a different (or the same) name but has been deleted. This may indicate that the file is inappropriate and should not be uploaded. Use -Force to ignore this warning.'
    }

    $Attempt    = 0 # Max three attempts before aborting
    $Retry = $false
    do
    {
      $Retry = $false

      $Response = Invoke-MWApiRequest @RequestParams

      if (-not $Force)
      {
        if ($Warnings = $Response.upload.warnings)
        {
          foreach ($Key in $Warnings.Keys)
          {
            if ($WarningMessages.Keys -contains $Key)
            { $Message = $WarningMessages.$Key }
            else
            { $Message = $Warnings.$Key }

            Write-Warning "[$Key] $Message"
          }
        }
      }

      if ($UploadErrors = $Response.errors)
      {
        foreach ($UploadError in $UploadErrors)
        {
          # Either the data is corrupt or the file extension and the file's MIME type don't correlate.
          if ($UploadError.code -eq 'verification-error')
          {
            if ($UploadError.text -like '*does not match the detected MIME type of the file*')
            {
              if ($FixExtension)
              {
                $Mime     = $UploadError.text -replace '.*\((.*)\)\.', '$1'
                $RightExt = $Extensions.$Mime
                $WrongExt = ("." + $Name.Split('.')[-1])

                if ($RightExt)
                {
                  $RequestParams.Body.filename = $RequestParams.Body.filename.Replace($WrongExt, $RightExt)
                  Write-Warning "Retrying upload using filename $($RequestParams.Body.filename)..."
                  $Retry = $true
                }
              }
            }
          }

          # URL based upload is disabled
          if ($UploadError.code -eq 'copyuploaddisabled')
          {
            Write-Host "URL based upload is disabled, attempting a local workaround..."
            $StatusCode = 200
            $Link       = $Url
            $ext        = $Link.Split('.')[-1]

            if ([string]::IsNullOrWhiteSpace($ext))
            { $ext = '.tmp' }

            $FilePath = "$env:Temp\mw-$(Get-Random).$ext"
            try {
              Write-Verbose "Downloading $Link..."
              Invoke-WebRequest -Uri $Link -Method GET -UseBasicParsing -DisableKeepAlive -OutFile $FilePath
            } catch {
              $StatusCode = $_.Exception.response.StatusCode.value__
            }

            if ($StatusCode -ne 200)
            {
              Write-Warning "Failed to download $Link !"
              return
            }

            if (-not (Test-Path $FilePath))
            {
              Write-Warning "Could not find $FilePath !"
              return
            }

            $FilePath = Get-Item $FilePath

            $FuncParams = @{
              Name         = $Name
              File         = $FilePath.FullName
              FixExtension = $true
              JSON         = $JSON
            }

            if ($Comment)
            { $FuncParams.Comment = $Comment }

            if ($Force)
            { $FuncParams.Force = $Force }

            if ($FileKey)
            { $FuncParams.FileKey = $FileKey }

            if ($Stash)
            { $FuncParams.Stash = $Stash }

            if ($Watchlist)
            { $FuncParams.Watchlist = $Watchlist }

            if ($Tags)
            { $FuncParams.Tags = $Tags }

            if ($JSON)
            { $FuncParams.JSON = $JSON }

            $Response = Import-MWFile @FuncParams
            
            # Do not forget to delete the temporary file after!
            Remove-Item -Path $FilePath.FullName -Force
          }
        }
      }
    } while ($Retry -and ++$Attempt -lt 3)

    if ($Attempt -eq 3)
    { Write-Warning 'Aborted after three failed attempt at retrying the request.' }

    if ($JSON)
    { return $Response }

    return $Response.upload | ForEach-Object { ConvertFrom-HashtableToPSObject $_ }
  }

  End { }
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

    [TokenType]$Token = [TokenType]::None,
    $Uri = ($script:Config.URI),
    [int32]$RateLimit = 60, # In seconds

    # Used by Import-MWFile
    [string]$ContentType,
    [string]$InFile,

    # Used by pretty much all cmdlets
    [Parameter(ParameterSetName = 'WebSession')]
    [Microsoft.PowerShell.Commands.WebRequestSession]
    $WebSession,

    # Used by Connect-MWSession
    [Parameter(ParameterSetName = 'SessionVariable')]
    [string]
    $SessionVariable,

    # Used by Disconnect-MWSession and Get-MWToken to not renew an expired CSRF/edit token
    [switch]$IgnoreDisconnect,
    # Used by Disconnect-MWSession and Get-MWToken and Connect-MWSession to suppress adding asserings to the calls
    [switch]$NoAssert,

    # Used to export errors/warnings to a JSON file
    [switch]$WriteIssuesToDisk
  )

  Begin { }

  Process
  {
    if ($WriteIssuesToDisk)
    { Write-Verbose '-WriteIssuesToDisk is being used. Any issues will be written to .\error.json and .\warnings.json.'}

    # Insert any required token
    if ($Token -ne [TokenType]::None)
    { $Body.token = Get-MWToken -Type $Token }

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

      # If we have signed out/in again, we need to renew the required token as it has expired
      if ($null -ne $Body.token -and $Body.token -ne (Get-MWToken -Type $Token))
      { $Body.token = (Get-MWToken -Type $Token) }

      $RequestParams    = @{
        Body            = $Body
        Uri             = $Uri
        Method          = $Method
        UseBasicParsing = $true
      }

      if ($ContentType -eq 'multipart/form-data')
      {
        $multipartBoundary = [System.Guid]::NewGuid().ToString()
        $multipartContent  = [System.Net.Http.MultipartFormDataContent]::new($multipartBoundary)
        $ContentType       = "multipart/form-data; boundary=`"$multipartBoundary`""

        # Convert $Body to $multipartContent
        foreach ($Key in $Body.Keys)
        {
          $StringHeader                             = [System.Net.Http.Headers.ContentDispositionHeaderValue]::new("form-data")
          $StringHeader.Name                        = "`"$Key`""
          $StringContent                            = [System.Net.Http.StringContent]::new($Body[$Key])
          $StringContent.Headers.ContentDisposition = $StringHeader
          $multipartContent.Add($stringContent)
        }
        
        if ($InFile)
        {
          if (-not (Test-Path $InFile))
          {
            Write-Warning '-InFile does not point to a file that exists!'
            return
          }

          # Read file
          $fileName                               = Split-Path $InFile -Leaf
          $fileBytes                              = [System.IO.File]::ReadAllBytes($InFile)
          $fileEncoding                           = [System.Text.Encoding]::GetEncoding('ISO-8859-1').GetString($fileBytes)

          $StringHeader                           = [System.Net.Http.Headers.ContentDispositionHeaderValue]::new('form-data')
          $StringHeader.Name                      = "`"file`""
          $StringHeader.FileName                  = "`"$FileName`""
          $fileContent                            = [System.Net.Http.StringContent]::new($fileEncoding)
          $fileContent.Headers.ContentDisposition = $StringHeader
          $fileContent.Headers.ContentType        = [System.Net.Http.Headers.MediaTypeHeaderValue]::Parse('application/octet-stream')
          $multipartContent.Add($fileContent)
        }

        $RequestParams.Body = $multipartContent.ReadAsStringAsync().Result
        #Write-Debug $Result
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
          WebSession      = Get-MWSession
        }
      }

      if (-not [string]::IsNullOrWhiteSpace($ContentType))
      {
        $RequestParams   += @{
          ContentType     = $ContentType
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
          if ($WriteIssuesToDisk)
          { $JsonObject.errors | ConvertTo-Json -Depth 100 | Out-File 'errors.json' }

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
          if ($WriteIssuesToDisk)
          { $JsonObject.warnings | ConvertTo-Json -Depth 100 | Out-File 'warnings.json' }

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
          { Write-Warning 'The session is being refreshed...' }
          else
          { Write-Warning 'The session has expired! Please sign in to continue, or press Ctrl + Z to abort.' }

          #Disconnect-MWSession # This will fail due to the expired session, so let us just clear the session data manually
          Clear-MWSession
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
Set-Alias -Name Rename-MWPage -Value Move-MWPage
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
    [Watchlist]$Watchlist = [Watchlist]::Preferences,
    
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
      watchlist = $Watchlist.ToString().ToLower()
    }

    if ($NoRedirect)
    { $Body.noredirect = $true }

    if (-not $SkipTalkPage)
    { $Body.movetalk = $true }

    if (-not $SkipSubpages)
    { $Body.movesubpages = $true }

    if ($Force)
    { $Body.ignorewarnings = $true }

    $ArrJSON += Invoke-MWApiRequest -Body $Body -Method POST -Token CSRF
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
  <#
  .SYNOPSIS
    Creates a new page on the site.

  .DESCRIPTION
    Creates a new page on the site, with optional parameters to indicate how to flag the edit.

  .PARAMETER Name
    Name of the page to be created.

  .PARAMETER Summary
    A short summary to attach to the edit.

  .PARAMETER Content
    Contents of the new page.

  .PARAMETER Wikitext
    Alias for the -Content parameter.

  .PARAMETER Watchlist
    Defines whether to add the page to the user's watchlist or not.

  .PARAMETER Recreate
    Switch used to indicate that the target page should be recreated if it has been deleted.

  .PARAMETER Bot
    Switch used to indicate the edit was performed by a bot.

  .PARAMETER Minor
    Switch used to indicate the edit is of a minor concern.

  .PARAMETER Major
    Switch used to indicate the edit is of a major concern.

  .PARAMETER Tags
    Tag the edit according to one or more tags available in Special:Tags

  .INPUTS
    Name (System.String) of the page to create.

  .INPUTS
    Summary (System.String) of the edit summary.

  .INPUTS
    Content (System.String) of the new page.

  .INPUTS
    Wikitext (System.String) as an alias for -Content.

  .OUTPUTS
    Returns a PSObject object containing the results of the edit.
  #>
  [CmdletBinding(DefaultParameterSetName = 'PageName')]
  param (
    <#
      Core parameters
    #>
    [Parameter(Mandatory, ValueFromPipelineByPropertyName, ParameterSetName = 'PageName', Position=0)]
    [ValidateNotNullOrEmpty()]
    [Alias('Title', 'Identity', 'PageName')]
    [string]$Name,

    [Parameter(ValueFromPipelineByPropertyName)]
    [AllowEmptyString()]
    [string]$Summary,

    [Parameter(ValueFromPipelineByPropertyName)]
    [AllowEmptyString()]
    [Alias('Text')]
    [string]$Content,

    # Alias for $Content, but in a way to support ValueFromPipelineByPropertyName
    [Parameter(ValueFromPipelineByPropertyName)]
    [AllowEmptyString()]
    [string]$Wikitext,

    <#
      Watchlist
    #>
    [Watchlist]$Watchlist = [Watchlist]::Preferences,

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
    [string[]]$Tags, # Tag the edit according to one or more tags available in Special:Tags

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

    if ($Content -and $Wikitext)
    {
      Write-Warning "-Content and -Wikitext cannot be used at the same time!"
      return $null
    }

    if ($Wikitext)
    { $Content = $Wikitext }

    $Parameters  = @{
      Name       = $Name
      Watchlist  = $Watchlist
      CreateOnly = $true
      JSON       = $JSON
    }

    if ($Summary)
    { $Parameters.Summary = $Summary }

    if ($Content)
    { $Parameters.Content = $Content }

    if ($Recreate)
    { $Parameters.Recreate = $Recreate }

    if ($Bot)
    { $Parameters.Bot = $Bot }

    if ($Minor)
    { $Parameters.Minor = $Minor }

    if ($Major)
    { $Parameters.Major = $Major }

    if ($Tags)
    { $Parameters.Tags = $Tags }

    return Set-MWPage @Parameters
  }

  End { }
}
#endregion

#region New-MWSection
function New-MWSection
{
  <#
  .SYNOPSIS
    Adds a new section to the given page.

  .DESCRIPTION
    The cmdlet is a front for Set-MWPage that makes it easier to add a new section to an existing page.

  .PARAMETER Name
    Name of the page to edit. Cannot be used alongside the -ID parameter.

  .PARAMETER ID
    ID of the page to edit. Cannot be used alongside the -Name parameter.

  .PARAMETER Summary
    A short summary to attach to the edit.

  .PARAMETER Content
    Contents of the new section.

  .PARAMETER Wikitext
    Alias for the -Content parameter.

  .PARAMETER Title
    The title of the new section.

  .PARAMETER BaseRevisionID
    ID of the base revision, used to detect edit conflicts.

  .PARAMETER BaseTimestamp
    Timestamp of the base revision, used to detect edit conflicts.

  .PARAMETER StartTimestamp
    Timestamp when the editing process began, used to detect edit conflicts.

  .PARAMETER Watchlist
    Defines whether to add the page to the user's watchlist or not.

  .PARAMETER FollowRedirects
    Switch to retrieve information about the target pages of any given redirect page, instead of the redirect page itself.

  .PARAMETER Bot
    Switch used to indicate the edit was performed by a bot.

  .PARAMETER Minor
    Switch used to indicate the edit is of a minor concern.

  .PARAMETER Minor
    Switch used to indicate the edit is of a major concern.

  .PARAMETER Tags
    Tag the edit according to one or more tags available in Special:Tags
    
  .INPUTS
    Name (System.String) of the page to edit. Cannot be used alongside the -ID parameter.

  .INPUTS
    ID (System.UInt32) of the page to edit. Cannot be used alongside the -Name parameter.

  .INPUTS
    Summary (System.String) of the edit summary.

  .INPUTS
    Content (System.String) of the new section.

  .INPUTS
    Wikitext (System.String) as an alias for -Content.

  .OUTPUTS
    Returns a PSObject object containing the results of the edit.
  #>
  [CmdletBinding(DefaultParameterSetName = 'PageName')]
  param (
    <#
      Core parameters
    #>
    [Parameter(Mandatory, ValueFromPipelineByPropertyName, ParameterSetName = 'PageName', Position=0)]
    [ValidateNotNullOrEmpty()]
    [Alias('Identity', 'PageName')]
    [string]$Name,

    [Parameter(Mandatory, ValueFromPipelineByPropertyName, ParameterSetName = 'PageID', Position=0)]
    [Alias('PageID')]
    [uint32]$ID,

    [Parameter(ValueFromPipelineByPropertyName)]
    [AllowEmptyString()]
    [string]$Summary,

    [Parameter(ValueFromPipelineByPropertyName)]
    [AllowEmptyString()]
    [Alias('Text')]
    [string]$Content,

    # Alias for $Content, but in a way to support ValueFromPipelineByPropertyName
    [Parameter(ValueFromPipelineByPropertyName)]
    [AllowEmptyString()]
    [string]$Wikitext,

    <#
      Section based stuff
    #>
    [Parameter(Mandatory)]
    [Alias('HeaderTitle', 'SectionTitle')]
    [string]$Title,

    <#
      Verification
    #>
    [Alias('BaseRevID')]
    [uint32]$BaseRevisionID,
    [string]$BaseTimestamp,
    [string]$StartTimestamp,

    <#
      Watchlist
    #>
    [Watchlist]$Watchlist = [Watchlist]::Preferences,

    <#
      Page related stuff
    #>
    [switch]$FollowRedirects, # Resolve redirects?

    <#
      Tags applied to the edit
    #>
    [switch]$Bot,
    [switch]$Minor,
    [switch]$Major,
    [string[]]$Tags, # Tag the edit according to one or more tags available in Special:Tags

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

    if ($Content -and $Wikitext)
    {
      Write-Warning "-Content and -Wikitext cannot be used at the same time!"
      return $null
    }

    if ($Wikitext)
    { $Content = $Wikitext }

    $Parameters = @{
      Section   = $true
      NoCreate  = $true
      JSON      = $JSON
    }

    if ($Name)
    { $Parameters.Name = $Name }

    if ($ID)
    { $Parameters.ID = $ID }

    if ($Summary)
    { $Parameters.Summary = $Summary }

    if ($Content)
    { $Parameters.Content = $Content }

    # Section stuff

    if ($Title)
    { $Parameters.SectionTitle = $Title }

    # Verification

    if ($BaseRevisionID)
    { $Parameters.BaseRevisionID = $BaseRevisionID }

    if ($BaseTimestamp)
    { $Parameters.BaseTimestamp = $BaseTimestamp }

    if ($StartTimestamp)
    { $Parameters.StartTimestamp = $StartTimestamp }

    # Watchlist

    if ($Watchlist)
    { $Parameters.Watchlist = $Watchlist }

    # Page stuff

    if ($FollowRedirects)
    { $Parameters.FollowRedirects = $FollowRedirects }

    # Edit tags

    if ($Bot)
    { $Parameters.Bot = $Bot }

    if ($Minor)
    { $Parameters.Minor = $Minor }

    if ($Major)
    { $Parameters.Major = $Major }

    if ($Tags)
    { $Parameters.Tags = $Tags }

    return Set-MWPage @Parameters
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
    [Parameter(Mandatory, ValueFromPipelineByPropertyName, ParameterSetName = 'PageName', Position=0)]
    [ValidateNotNullOrEmpty()]
    [Alias('Title', 'Identity', 'PageName')]
    [string[]]$Name,

    [Parameter(Mandatory, ValueFromPipelineByPropertyName, ParameterSetName = 'PageID', Position=0)]
    [Alias('PageID')]
    [int[]]$ID,

    [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
    [AllowEmptyString()]
    [string]$Reason,

    <#
      Watchlist
    #>
    [Watchlist]$Watchlist = [Watchlist]::Preferences,

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
        watchlist = $Watchlist.ToString().ToLower()
      }

      if ($ID)
      { $Body.pageid = $Page }
      else
      { $Body.title = $Page }

      $ArrJSON += Invoke-MWApiRequest -Body $Body -Method POST -Token CSRF
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

#region Remove-MWSection
function Remove-MWSection
{
  <#
  .SYNOPSIS
    Removes the specified section on the given page.

  .DESCRIPTION
    The cmdlet is a front for Set-MWPage that makes it easier to add new text to an existing section on pages.

  .PARAMETER Name
    Name of the page to edit. Cannot be used alongside the -ID parameter.

  .PARAMETER ID
    ID of the page to edit. Cannot be used alongside the -Name parameter.

  .PARAMETER Summary
    A short summary to attach to the edit.

  .PARAMETER Index
    The section index to remove, retrieved through Get-MWPage.

  .PARAMETER BaseRevisionID
    ID of the base revision, used to detect edit conflicts.

  .PARAMETER BaseTimestamp
    Timestamp of the base revision, used to detect edit conflicts.

  .PARAMETER StartTimestamp
    Timestamp when the editing process began, used to detect edit conflicts.

  .PARAMETER Watchlist
    Defines whether to add the page to the user's watchlist or not.

  .PARAMETER FollowRedirects
    Switch to retrieve information about the target pages of any given redirect page, instead of the redirect page itself.

  .PARAMETER Bot
    Switch used to indicate the edit was performed by a bot.

  .PARAMETER Minor
    Switch used to indicate the edit is of a minor concern.

  .PARAMETER Minor
    Switch used to indicate the edit is of a major concern.

  .PARAMETER Tags
    Tag the edit according to one or more tags available in Special:Tags
    
  .INPUTS
    Name (System.String) of the page to edit. Cannot be used alongside the -ID parameter.
    
  .INPUTS
    FromTitle (System.String) as an alias for -Name.

  .INPUTS
    ID (System.UInt32) of the page to edit. Cannot be used alongside the -Name parameter.

  .INPUTS
    Summary (System.String) of the edit summary.

  .INPUTS
    Index (System.UInt32) of the section to edit.

  .OUTPUTS
    Returns a PSObject object containing the results of the edit.
  #>
  [CmdletBinding(DefaultParameterSetName = 'PageName')]
  param (
    <#
      Core parameters
    #>
    [Parameter(Mandatory, ValueFromPipelineByPropertyName, ParameterSetName = 'PageName', Position=0)]
    [ValidateNotNullOrEmpty()]
    [Alias('Title', 'Identity', 'PageName')]
    [string]$Name,

    # Alias for $Name, but in a way to support ValueFromPipelineByPropertyName
    [Parameter(Mandatory, ValueFromPipelineByPropertyName, ParameterSetName = 'FromTitle', Position=0)]
    [ValidateNotNullOrEmpty()]
    [string]$FromTitle,

    [Parameter(Mandatory, ValueFromPipelineByPropertyName, ParameterSetName = 'PageID', Position=0)]
    [Alias('PageID')]
    [uint32]$ID,

    [Parameter(ValueFromPipelineByPropertyName)]
    [AllowEmptyString()]
    [string]$Summary,

    <#
      Section based stuff
    #>
    [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
    [Alias('SectionIndex')]
    [uint32]$Index,

    <#
      Verification
    #>
    [Alias('BaseRevID')]
    [uint32]$BaseRevisionID,
    [string]$BaseTimestamp,
    [string]$StartTimestamp,

    <#
      Watchlist
    #>
    [Watchlist]$Watchlist = [Watchlist]::Preferences,

    <#
      Page related stuff
    #>
    [switch]$FollowRedirects, # Resolve redirects?

    <#
      Tags applied to the edit
    #>
    [switch]$Bot,
    [switch]$Minor,
    [switch]$Major,
    [string[]]$Tags, # Tag the edit according to one or more tags available in Special:Tags

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

    if ($FromTitle)
    { $Name = $FromTitle }

    $Parameters    = @{
      Section      = $true
      SectionIndex = $Index
     #SectionTitle = '' # Remove the header
      Content      = '' # Remove the body
      NoCreate     = $true
      JSON         = $JSON
    }

    if ($Name)
    { $Parameters.Name = $Name }

    if ($ID)
    { $Parameters.ID = $ID }

    if ($Summary)
    { $Parameters.Summary = $Summary }

    # Verification

    if ($BaseRevisionID)
    { $Parameters.BaseRevisionID = $BaseRevisionID }

    if ($BaseTimestamp)
    { $Parameters.BaseTimestamp = $BaseTimestamp }

    if ($StartTimestamp)
    { $Parameters.StartTimestamp = $StartTimestamp }

    # Watchlist

    if ($Watchlist)
    { $Parameters.Watchlist = $Watchlist }

    # Page stuff

    if ($FollowRedirects)
    { $Parameters.FollowRedirects = $FollowRedirects }

    # Edit tags

    if ($Bot)
    { $Parameters.Bot = $Bot }

    if ($Minor)
    { $Parameters.Minor = $Minor }

    if ($Major)
    { $Parameters.Major = $Major }

    if ($Tags)
    { $Parameters.Tags = $Tags }

    return Set-MWPage @Parameters
  }

  End { }
}
#endregion

#region Rename-MWSection
function Rename-MWSection
{
  <#
  .SYNOPSIS
    Rename the specified section on the given page to a new title.

  .DESCRIPTION
    The cmdlet is a front for Set-MWPage that makes it easier to rename a specific section.

  .PARAMETER Name
    Name of the page to edit. Cannot be used alongside the -ID parameter.

  .PARAMETER FromTitle
    Alias for the -Name parameter.

  .PARAMETER ID
    ID of the page to edit. Cannot be used alongside the -Name parameter.

  .PARAMETER Summary
    A short summary to attach to the edit.

  .PARAMETER Index
    The section index to edit, retrieved through Get-MWPage.

  .PARAMETER NewTitle
    The new title of the section.

  .PARAMETER BaseRevisionID
    ID of the base revision, used to detect edit conflicts.

  .PARAMETER BaseTimestamp
    Timestamp of the base revision, used to detect edit conflicts.

  .PARAMETER StartTimestamp
    Timestamp when the editing process began, used to detect edit conflicts.

  .PARAMETER Watchlist
    Defines whether to add the page to the user's watchlist or not.

  .PARAMETER FollowRedirects
    Switch to retrieve information about the target pages of any given redirect page, instead of the redirect page itself.

  .PARAMETER Bot
    Switch used to indicate the edit was performed by a bot.

  .PARAMETER Minor
    Switch used to indicate the edit is of a minor concern.

  .PARAMETER Minor
    Switch used to indicate the edit is of a major concern.

  .PARAMETER Tags
    Tag the edit according to one or more tags available in Special:Tags
      
  .INPUTS
    Name (System.String) of the page to edit. Cannot be used alongside the -ID parameter.
    
  .INPUTS
    FromTitle (System.String) as an alias for -Name.

  .INPUTS
    ID (System.UInt32) of the page to edit. Cannot be used alongside the -Name parameter.

  .INPUTS
    Summary (System.String) of the edit summary.

  .INPUTS
    Index (System.UInt32) of the section to edit.

  .INPUTS
    NewTitle (System.String) to rename the section to.

  .OUTPUTS
    Returns a PSObject object containing the results of the edit.
  #>
  [CmdletBinding(DefaultParameterSetName = 'PageName')]
  param (
    <#
      Core parameters
    #>
    [Parameter(Mandatory, ValueFromPipelineByPropertyName, ParameterSetName = 'PageName', Position=0)]
    [ValidateNotNullOrEmpty()]
    [Alias('Title', 'Identity', 'PageName')]
    [string]$Name,

    # Alias for $Name, but in a way to support ValueFromPipelineByPropertyName
    [Parameter(Mandatory, ValueFromPipelineByPropertyName, ParameterSetName = 'FromTitle', Position=0)]
    [ValidateNotNullOrEmpty()]
    [string]$FromTitle,

    [Parameter(Mandatory, ValueFromPipelineByPropertyName, ParameterSetName = 'PageID', Position=0)]
    [Alias('PageID')]
    [uint32]$ID,

    [Parameter(ValueFromPipelineByPropertyName)]
    [AllowEmptyString()]
    [string]$Summary,

    <#
      Section based stuff
    #>
    [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
    [Alias('SectionIndex')]
    [uint32]$Index,

    [Parameter(ValueFromPipelineByPropertyName)]
    [Alias('NewSectionTitle')]
    [string]$NewTitle,

    <#
      Verification
    #>
    [Alias('BaseRevID')]
    [uint32]$BaseRevisionID,
    [string]$BaseTimestamp,
    [string]$StartTimestamp,

    <#
      Watchlist
    #>
    [Watchlist]$Watchlist = [Watchlist]::Preferences,

    <#
      Page related stuff
    #>
    [switch]$FollowRedirects, # Resolve redirects?

    <#
      Tags applied to the edit
    #>
    [switch]$Bot,
    [switch]$Minor,
    [switch]$Major,
    [string[]]$Tags, # Tag the edit according to one or more tags available in Special:Tags

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

    if ($FromTitle)
    { $Name = $FromTitle }

    $Current = @{
      Wikitext     = $true
      SectionIndex = $Index
    }

    if ($Name)
    { $Current.Name = $Name }
    
    if ($ID)
    { $Current.ID = $ID }

    $SectionContent = Get-MWSection @Current

    if ($null -eq $SectionContent)
    {
      Write-Warning 'Could not retrieve section content from the specified page!'
      return $null
    }

    # Header will always be the first line of the section content
    $CurrentTitle = (($SectionContent.Wikitext) -split '\n')[0]
    $SectionTitle = $CurrentTitle -replace '(^={1,6})[^=]+(={1,6}\s*?$)', "`$1$NewTitle`$2"

    $NewContent = $SectionContent.Wikitext.Replace($CurrentTitle, $SectionTitle)

    $Parameters    = @{
      Section      = $true
      SectionIndex = $Index
      Content      = $NewContent
      NoCreate     = $true
      JSON         = $JSON
    }

    if ($Name)
    { $Parameters.Name = $Name }

    if ($ID)
    { $Parameters.ID = $ID }

    if ($Summary)
    { $Parameters.Summary = $Summary }

    # Verification

    if ($BaseRevisionID)
    { $Parameters.BaseRevisionID = $BaseRevisionID }

    if ($BaseTimestamp)
    { $Parameters.BaseTimestamp = $BaseTimestamp }

    if ($StartTimestamp)
    { $Parameters.StartTimestamp = $StartTimestamp }

    # Watchlist

    if ($Watchlist)
    { $Parameters.Watchlist = $Watchlist }

    # Page stuff

    if ($FollowRedirects)
    { $Parameters.FollowRedirects = $FollowRedirects }

    # Edit tags

    if ($Bot)
    { $Parameters.Bot = $Bot }

    if ($Minor)
    { $Parameters.Minor = $Minor }

    if ($Major)
    { $Parameters.Major = $Major }

    if ($Tags)
    { $Parameters.Tags = $Tags }

    return Set-MWPage @Parameters
  }

  End { }
}
#endregion

#region Search-MWPage
# Not to be mistaken for Find-MWPage!
function Search-MWPage
{
  [CmdletBinding(DefaultParameterSetName = 'SearchByText')]
  param
  (
    [Parameter(Mandatory, ValueFromPipelineByPropertyName, Position=0)]
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
  <#
  .SYNOPSIS
    Create and edit pages.

  .DESCRIPTION
    Base function responsible for all page edits and creations, and supports a wide array of parameters as a result.

  .PARAMETER Name
    Name of the page to edit. Cannot be used alongside the -ID parameter.

  .PARAMETER ID
    ID of the page to edit. Cannot be used alongside the -Name parameter.

  .PARAMETER Summary
    A short summary to attach to the edit.

  .PARAMETER Content
    Contents of the new section.

  .PARAMETER Wikitext
    Alias for the -Content parameter.

  .PARAMETER Append
    Switch used to indicate that the specified -Content should be appended to the page or specified -SectionIndex.

  .PARAMETER Prepend
    Switch used to indicate that the specified -Content should be prepended to the page or specified -SectionIndex.

  .PARAMETER Section
    Switch used to indicate that the edit concerns section should be added.

  .PARAMETER SectionIndex
    The section index to edit. If omitted, a new section will be created.

  .PARAMETER SectionTitle
    The title of the new section.

  .PARAMETER BaseRevisionID
    ID of the base revision, used to detect edit conflicts.

  .PARAMETER BaseTimestamp
    Timestamp of the base revision, used to detect edit conflicts.

  .PARAMETER StartTimestamp
    Timestamp when the editing process began, used to detect edit conflicts.

  .PARAMETER Watchlist
    Defines whether to add the page to the user's watchlist or not.

  .PARAMETER Recreate
    Switch used to indicate that the target page should be recreated if it has been deleted.

  .PARAMETER CreateOnly
    Switch used to indicate that the edit should create a new page; does not apply the edit on an existing page.

  .PARAMETER NoCreate
    Switch used to indicate that the edit should not result in the creation of a new page; only applies the edit on an existing page.

  .PARAMETER FollowRedirects
    Switch to retrieve information about the target pages of any given redirect page, instead of the redirect page itself.

  .PARAMETER Bot
    Switch used to indicate the edit was performed by a bot.

  .PARAMETER Minor
    Switch used to indicate the edit is of a minor concern.

  .PARAMETER Minor
    Switch used to indicate the edit is of a major concern.

  .PARAMETER Tags
    Tag the edit according to one or more tags available in Special:Tags

  .PARAMETER Undo
    Switch used to indicate that an edit should be undone. Cannot be used with -Content, -Wikitext, -Append, or -Prepend.

  .PARAMETER RevisionID
    The revision ID to undo, or the revision ID to start undoing from if specifying a range to undo.

  .PARAMETER EndRevisionID
    The revision ID to stop undoing at. Will only undo one edit if unused.
    
  .INPUTS
    Name (System.String) of the page to edit. Cannot be used alongside the -ID parameter.

  .INPUTS
    ID (System.UInt32) of the page to edit. Cannot be used alongside the -Name parameter.

  .INPUTS
    Summary (System.String) of the edit summary.

  .INPUTS
    Content (System.String) of the new section.

  .INPUTS
    Wikitext (System.String) as an alias for -Content.

  .OUTPUTS
    Returns a PSObject object containing the results of the edit.
  #>
  [CmdletBinding(DefaultParameterSetName = 'PageName')]
  param (
    <#
      Core parameters
    #>
    [Parameter(Mandatory, ValueFromPipelineByPropertyName, ParameterSetName = 'PageName', Position=0)]
    [Parameter(Mandatory, ValueFromPipelineByPropertyName, ParameterSetName = 'PageNameUndo', Position=0)]
    [ValidateNotNullOrEmpty()]
    [Alias('Title', 'Identity', 'PageName')]
    [string]$Name,

    [Parameter(Mandatory, ValueFromPipelineByPropertyName, ParameterSetName = 'PageID', Position=0)]
    [Parameter(Mandatory, ValueFromPipelineByPropertyName, ParameterSetName = 'PageIDUndo', Position=0)]
    [Alias('PageID')]
    [uint32]$ID,

    [Parameter(ValueFromPipelineByPropertyName)]
    [AllowEmptyString()]
    [string]$Summary,

    [Parameter(ValueFromPipelineByPropertyName, ParameterSetName = 'PageName')]
    [Parameter(ValueFromPipelineByPropertyName, ParameterSetName = 'PageID')]
    [AllowEmptyString()]
    [Alias('Text')]
    [string]$Content,

    # Alias for $Content, but in a way to support ValueFromPipelineByPropertyName
    [Parameter(ValueFromPipelineByPropertyName, ParameterSetName = 'PageName')]
    [Parameter(ValueFromPipelineByPropertyName, ParameterSetName = 'PageID')]
    [AllowEmptyString()]
    [string]$Wikitext,

    <#
      Section based stuff
    #>
    [switch]$Section,
    [uint32]$SectionIndex = $null,
    [string]$SectionTitle,

    <#
      Append / Prepend
    #>
    [Parameter(ParameterSetName = 'PageName')]
    [Parameter(ParameterSetName = 'PageID')]
    [Alias('AppendText')]
    [switch]$Append,

    [Parameter(ParameterSetName = 'PageName')]
    [Parameter(ParameterSetName = 'PageID')]
    [Alias('PrependText')]
    [switch]$Prepend,

    <#
      Verification
    #>
    [Alias('BaseRevID')]
    [uint32]$BaseRevisionID,
    [string]$BaseTimestamp,
    [string]$StartTimestamp,

    <#
      Watchlist
    #>
    [Watchlist]$Watchlist = [Watchlist]::Preferences,

    <#
      Page related stuff
    #>
    [switch]$Recreate,
    [switch]$CreateOnly,
    [switch]$NoCreate,
    [switch]$FollowRedirects,

    <#
      Tags applied to the edit
    #>
    [switch]$Bot,
    [switch]$Minor,
    [switch]$Major,
    [ValidateScript({ Test-MWChangeTag -InputObject $PSItem })]
    [string[]]$Tags, # Tag the edit according to one or more tags available in Special:Tags

    <#
      Undo
    #>
    [Parameter(ParameterSetName = 'PageNameUndo')]
    [Parameter(ParameterSetName = 'PageIDUndo')]
    [switch]$Undo,
    
    [Parameter(Mandatory, ParameterSetName = 'PageNameUndo')]
    [Parameter(Mandatory, ParameterSetName = 'PageIDUndo')]
    [ValidateRange(0, [uint32]::MaxValue)]
    [uint32]$RevisionID, # Undo this revision. Use 0 to undo all history and blank the page.

    [Parameter(ParameterSetName = 'PageNameUndo')]
    [Parameter(ParameterSetName = 'PageIDUndo')]
    [ValidateRange(1, [uint32]::MaxValue)]
    [uint32]$EndRevisionID, # Undo all revisions from -UndoRevision to this one. If not set, undo a single revision.

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

    if ($Content -and $Wikitext)
    {
      Write-Warning "-Content and -Wikitext cannot be used at the same time!"
      return $null
    }

    if ($Wikitext)
    { $Content = $Wikitext }

    $JoinedTags     = ''

    if ($Tags)
    { $JoinedTags = $Tags -join '|' }

    $Body = [ordered]@{
      action    = 'edit'
      watchlist = $Watchlist.ToString().ToLower()
    }

    $PageIdentity = ''

    if ($ID)
    {
      $PageIdentity = $ID
      $Body.pageid = $ID
    }
    else
    {
      $PageIdentity = $Name
      $Body.title = $Name
    }

    if ($Summary)
    { $Body.summary = $Summary }

    if ($Section)
    {
      if ($null -ne $SectionIndex)
      { $Body.section = $SectionIndex } # Assume section index (or 'new')
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

    if ($FollowRedirects)
    { $Body.redirect = $true } # Automatically resolve redirects. Omit if false

    if ($Bot)
    { $Body.bot = $true } # Omit if false

    if ($Major)
    { $Body.notminor = $true } # Omit if false
    elseif ($Minor)
    { $Body.minor = $true } # Omit if false
    else
    { } # Default to user preference

    if (-not [string]::IsNullOrEmpty($JoinedTags))
    { $Body.tags = $JoinedTags }

    if ($Undo)
    {
      $Body.undo = $RevisionID

      if ($EndRevisionID -gt 0)
      { $Body.undoafter = $EndRevisionID }
    }
    
    else
    {
      if ($Append)
      { $Body.appendtext = $Content }
      elseif ($Prepend)
      { $Body.prependtext = $Content }
      else
      { $Body.text = $Content }
    }

    if ($BaseRevisionID)
    { $Body.baserevid = $BaseRevisionID }

    if ($BaseTimestamp)
    { $Body.basetimestamp = $BaseTimestamp }

    if ($StartTimestamp)
    { $Body.starttimestamp = $StartTimestamp }

    $RateLimit = if ($script:Cache.UserInfo.RateLimits.Edit.User)
                    {$script:Cache.UserInfo.RateLimits.Edit.User}
               else {$script:Cache.UserInfo.RateLimits.Edit.IP  }

    Write-Verbose "Editing page $PageIdentity."

    $Response = Invoke-MWApiRequest -Body $Body -Method POST -Token CSRF -RateLimit $RateLimit.Seconds

    if ($JSON)
    { return $Response }

    $PSCustomObject = $null

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
          Write-Warning ('Page was created as a result of this edit: ' + $script:Cache.SiteInfo.General.Server + '/wiki/' + ($Page.title.Replace(' ', '_')))
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
      { Write-Warning "Error editing page $PageIdentity." }
    }

    return $PSCustomObject
  }

  End { }
}
#endregion

#region Set-MWSection
function Set-MWSection
{
  <#
  .SYNOPSIS
    Sets the content of the specified section on the given page.

  .DESCRIPTION
    The cmdlet is a front for Set-MWPage that makes it easier to set the text of a section on a page.

  .PARAMETER Name
    Name of the page to edit. Cannot be used alongside the -ID parameter.

  .PARAMETER FromTitle
    Alias for the -Name parameter.

  .PARAMETER ID
    ID of the page to edit. Cannot be used alongside the -Name parameter.

  .PARAMETER Summary
    A short summary to attach to the edit.

  .PARAMETER Content
    Content to change the specified section to.

  .PARAMETER Wikitext
    Alias for the -Content parameter.

  .PARAMETER Index
    The section index to edit, retrieved through Get-MWPage.

  .PARAMETER BaseRevisionID
    ID of the base revision, used to detect edit conflicts.

  .PARAMETER BaseTimestamp
    Timestamp of the base revision, used to detect edit conflicts.

  .PARAMETER StartTimestamp
    Timestamp when the editing process began, used to detect edit conflicts.

  .PARAMETER Watchlist
    Defines whether to add the page to the user's watchlist or not.

  .PARAMETER FollowRedirects
    Switch to retrieve information about the target pages of any given redirect page, instead of the redirect page itself.

  .PARAMETER Bot
    Switch used to indicate the edit was performed by a bot.

  .PARAMETER Minor
    Switch used to indicate the edit is of a minor concern.

  .PARAMETER Minor
    Switch used to indicate the edit is of a major concern.

  .PARAMETER Tags
    Tag the edit according to one or more tags available in Special:Tags
    
  .INPUTS
    Name (System.String) of the page to edit. Cannot be used alongside the -ID parameter.
    
  .INPUTS
    FromTitle (System.String) as an alias for -Name.

  .INPUTS
    ID (System.UInt32) of the page to edit. Cannot be used alongside the -Name parameter.

  .INPUTS
    Summary (System.String) of the edit summary.

  .INPUTS
    Index (System.UInt32) of the section to edit.

  .OUTPUTS
    Returns a PSObject object containing the results of the edit.
  #>
  [CmdletBinding(DefaultParameterSetName = 'PageName')]
  param (
    <#
      Core parameters
    #>
    [Parameter(Mandatory, ValueFromPipelineByPropertyName, ParameterSetName = 'PageName', Position=0)]
    [ValidateNotNullOrEmpty()]
    [Alias('Title', 'Identity', 'PageName')]
    [string]$Name,

    # Alias for $Name, but in a way to support ValueFromPipelineByPropertyName
    [Parameter(Mandatory, ValueFromPipelineByPropertyName, ParameterSetName = 'FromTitle', Position=0)]
    [ValidateNotNullOrEmpty()]
    [string]$FromTitle,

    [Parameter(Mandatory, ValueFromPipelineByPropertyName, ParameterSetName = 'PageID', Position=0)]
    [Alias('PageID')]
    [uint32]$ID,

    [Parameter(ValueFromPipelineByPropertyName)]
    [AllowEmptyString()]
    [string]$Summary,

    [Parameter(ValueFromPipelineByPropertyName)]
    [AllowEmptyString()]
    [Alias('Text')]
    [string]$Content,

    # Alias for $Content, but in a way to support ValueFromPipelineByPropertyName
    [Parameter(ValueFromPipelineByPropertyName)]
    [AllowEmptyString()]
    [string]$Wikitext,

    <#
      Section based stuff
    #>
    [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
    [Alias('SectionIndex')]
    [uint32]$Index,

    <#
      Verification
    #>
    [Alias('BaseRevID')]
    [uint32]$BaseRevisionID,
    [string]$BaseTimestamp,
    [string]$StartTimestamp,

    <#
      Watchlist
    #>
    [Watchlist]$Watchlist = [Watchlist]::Preferences,

    <#
      Page related stuff
    #>
    [switch]$FollowRedirects, # Resolve redirects?

    <#
      Tags applied to the edit
    #>
    [switch]$Bot,
    [switch]$Minor,
    [switch]$Major,
    [string[]]$Tags, # Tag the edit according to one or more tags available in Special:Tags

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

    if ($Content -and $Wikitext)
    {
      Write-Warning "-Content and -Wikitext cannot be used at the same time!"
      return $null
    }

    if ($FromTitle)
    { $Name = $FromTitle }

    if ($Wikitext)
    { $Content = $Wikitext }

    #if ($Prepend -and $Content -notmatch "\n$")
    #{ $Content += "`n" }

    $Current = @{
      Wikitext     = $true
      SectionIndex = $Index
    }

    if ($Name)
    { $Current.Name = $Name }
    
    if ($ID)
    { $Current.ID = $ID }

    $SectionContent = Get-MWSection @Current

    if ($null -eq $SectionContent)
    {
      Write-Warning 'Could not retrieve section content from the specified page!'
      return $null
    }

    # Header will always be the first line of the section content
    $SectionTitle = (($SectionContent.Wikitext) -split '\n')[0]

    $NewContent = ($SectionTitle + "`n" + $Content)

    $Parameters    = @{
      Section      = $true
      SectionIndex = $Index
      Content      = $NewContent
      NoCreate     = $true
      JSON         = $JSON
    }

    if ($Name)
    { $Parameters.Name = $Name }

    if ($ID)
    { $Parameters.ID = $ID }

    if ($Summary)
    { $Parameters.Summary = $Summary }

    # Verification

    if ($BaseRevisionID)
    { $Parameters.BaseRevisionID = $BaseRevisionID }

    if ($BaseTimestamp)
    { $Parameters.BaseTimestamp = $BaseTimestamp }

    if ($StartTimestamp)
    { $Parameters.StartTimestamp = $StartTimestamp }

    # Watchlist

    if ($Watchlist)
    { $Parameters.Watchlist = $Watchlist }

    # Page stuff

    if ($FollowRedirects)
    { $Parameters.FollowRedirects = $FollowRedirects }

    # Edit tags

    if ($Bot)
    { $Parameters.Bot = $Bot }

    if ($Minor)
    { $Parameters.Minor = $Minor }

    if ($Major)
    { $Parameters.Major = $Major }

    if ($Tags)
    { $Parameters.Tags = $Tags }

    return Set-MWPage @Parameters
  }

  End { }
}
#endregion

#region Undo-MWPageEdit
function Undo-MWPageEdit
{
  <#
  .SYNOPSIS
    Undo edits on a page.

  .DESCRIPTION
    Undo the specified edits of a page or all edits made by the last user to edit the page.

  .PARAMETER Name
    Name of the page to edit. Cannot be used alongside the -ID parameter.

  .PARAMETER ID
    ID of the page to edit. Cannot be used alongside the -Name parameter.

  .PARAMETER Summary
    A short summary to attach to the edit.

  .PARAMETER RevisionID
    The revision ID to undo, or the revision ID to start undoing from if specifying a range to undo.

  .PARAMETER EndRevisionID
    The revision ID to stop undoing at. Will only undo one edit if unused.

  .PARAMETER Rollback
    Switch used to indicate that all edits of the specified user should be rolled back.
    Must be used together with -User.

  .PARAMETER User
    Username, ID (#12345), or IP address of the user whose edits are to be rolled back.
    Must be used together with -Rollback.

  .PARAMETER Watchlist
    Defines whether to add the page to the user's watchlist or not.

  .PARAMETER Bot
    Switch used to indicate the edit was performed by a bot.

  .PARAMETER Minor
    Switch used to indicate the edit is of a minor concern.

  .PARAMETER Minor
    Switch used to indicate the edit is of a major concern.

  .PARAMETER Tags
    Tag the edit according to one or more tags available in Special:Tags
    
  .INPUTS
    Name (System.String) of the page to edit. Cannot be used alongside the -ID parameter.

  .INPUTS
    ID (System.UInt32) of the page to edit. Cannot be used alongside the -Name parameter.

  .INPUTS
    Summary (System.String) of the edit summary.

  .INPUTS
    RevisionID (System.UInt32) of the edit to undo.

  .OUTPUTS
    Returns a PSObject object containing the results of the edit.
  #>
  [CmdletBinding(DefaultParameterSetName = 'PageNameUndo')]
  param (
    <#
      Core parameters
    #>
    [Parameter(Mandatory, ValueFromPipelineByPropertyName, ParameterSetName = 'PageNameUndo', Position=0)]
    [Parameter(Mandatory, ValueFromPipelineByPropertyName, ParameterSetName = 'PageNameRollback', Position=0)]
    [ValidateNotNullOrEmpty()]
    [Alias('Title', 'Identity', 'PageName')]
    [string]$Name,

    [Parameter(Mandatory, ValueFromPipelineByPropertyName, ParameterSetName = 'PageIDUndo', Position=0)]
    [Parameter(Mandatory, ValueFromPipelineByPropertyName, ParameterSetName = 'PageIDRollback', Position=0)]
    [Alias('PageID')]
    [uint32]$ID,

    [Parameter(ValueFromPipelineByPropertyName)]
    [AllowEmptyString()]
    [string]$Summary,

    <#
      Undo
    #>
    [Parameter(Mandatory, ValueFromPipelineByPropertyName, ParameterSetName = 'PageNameUndo')]
    [Parameter(Mandatory, ValueFromPipelineByPropertyName, ParameterSetName = 'PageIDUndo')]
    [ValidateRange(0, [uint32]::MaxValue)]
    [uint32]$RevisionID, # Undo this revision. Use 0 to undo all history and blank the page.

    [Parameter(ParameterSetName = 'PageNameUndo')]
    [Parameter(ParameterSetName = 'PageIDUndo')]
    [ValidateRange(1, [uint32]::MaxValue)]
    [uint32]$EndRevisionID, # Undo all revisions from -UndoRevision to this one. If not set, undo a single revision.

    <#
      Rollback
    #>
    [Parameter(ParameterSetName = 'PageNameRollback')]
    [Parameter(ParameterSetName = 'PageIDRollback')]
    [switch]$Rollback,

    [Parameter(Mandatory, ParameterSetName = 'PageNameRollback')]
    [Parameter(Mandatory, ParameterSetName = 'PageIDRollback')]
    [string]$User,

    <#
      Watchlist
    #>
    [Watchlist]$Watchlist = [Watchlist]::Preferences,

    <#
      Tags applied to the edit
    #>
    [switch]$Bot,

    [Parameter(ParameterSetName = 'PageNameUndo')]
    [Parameter(ParameterSetName = 'PageIDUndo')]
    [switch]$Minor,

    [Parameter(ParameterSetName = 'PageNameUndo')]
    [Parameter(ParameterSetName = 'PageIDUndo')]
    [switch]$Major,

    [ValidateScript({ Test-MWChangeTag -InputObject $PSItem })]
    [string[]]$Tags, # Tag the edit according to one or more tags available in Special:Tags

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

    # Regular undo
    if (-not $Rollback)
    {
      $Parameters  = @{
        Undo       = $true
        RevisionID = $RevisionID
        Watchlist  = $Watchlist.ToString().ToLower()
      }

      if ($EndRevisionID -gt 0)
      { $Parameters.EndRevisionID = $EndRevisionID }

      if ($ID)
      { $Parameters.ID = $ID }
      else
      { $Parameters.Name = $Name }

      if ($Summary)
      { $Parameters.Summary = $Summary }

      if ($Bot)
      { $Parameters.Bot = $true }

      if ($Major)
      { $Parameters.Major = $true }
      elseif ($Minor)
      { $Parameters.Minor = $true }

      if ($Tags)
      { $Parameters.Tags = $Tags }

      return Set-MWPage @Parameters
    }

    # Rollback
    else
    {
      $JoinedTags     = ''

      if ($Tags)
      { $JoinedTags = $Tags -join '|' }

      $Body = [ordered]@{
        action    = 'rollback'
        user      = $User
        watchlist = $Watchlist.ToString().ToLower()
      }

      $PageIdentity = ''

      if ($ID)
      {
        $PageIdentity = $ID
        $Body.pageid = $ID
      }
      else
      {
        $PageIdentity = $Name
        $Body.title = $Name
      }

      if ($Summary)
      { $Body.summary = $Summary }

      if ($Bot)
      { $Body.markbot = $true } # Omit if false

      if (-not [string]::IsNullOrEmpty($JoinedTags))
      { $Body.tags = $JoinedTags }

      $RateLimit = if ($script:Cache.UserInfo.RateLimits.Rollback.User)
                      {$script:Cache.UserInfo.RateLimits.Rollback.User}
                 else {$script:Cache.UserInfo.RateLimits.Rollback.IP  }

      Write-Verbose "Rolling back page $PageIdentity."

      $Response = Invoke-MWApiRequest -Body $Body -Method POST -Token Rollback -RateLimit $RateLimit.Seconds

      if ($JSON)
      { return $Response }

      $PSCustomObject = $null

      if ($Page = $Response.rollback)
      {
        $ObjectProperties = [ordered]@{
         #Namespace          = $Page.ns
          ID                 = $Page.pageid
          Name               = $Page.title
          RevisionID         = $Page.revid
          PreviousRevisionID = $Page.old_revid
          RestoredRevisionID = $Page.last_revid
          Summary            = $Page.summary
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

      return $PSCustomObject
    }
  }

  End { }
}
#endregion

#region Update-MWCargoTable
function Update-MWCargoTable
{
  [CmdletBinding()]
  param
  (
    [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
    [string]$Table, # The Cargo database table which to update

    [switch]$UpdateOnlyMissingInReplacementTable,
    [switch]$Random,
    
    <#
      Debug
    #>
    [switch]$JSON
  )

  Begin
  {
    $ArrPSCustomObject = @()
  }

  Process
  {
    if ($null -eq $script:Config.URI)
    {
      Write-Warning "Not connected to a MediaWiki instance."
      return $null
    }

    if ($UpdateOnlyMissingInReplacementTable)
    {
      # Note that DISTINCT does not work in Cargo, so in most cases you must use "group by" to eliminate duplicates.
      $ReplacementTable = Get-MWCargoQuery -Tables ($Table + '__NEXT') -ResultSize Unlimited -GroupBy '_pageID,_pageName,_pageNamespace'

      if ($null -eq $ReplacementTable)
      {
        Write-Warning "No replacement table have been created!"
        return $null
      }
    }

    # Note that DISTINCT does not work in Cargo, so in most cases you must use "group by" to eliminate duplicates.
    $Pages = Get-MWCargoQuery -Tables $Table -ResultSize Unlimited -GroupBy '_pageID,_pageName,_pageNamespace'

    if ($null -eq $Pages)
    {
      Write-Warning 'The specified Cargo table could not be found or does not contain any rows.'
      return $null
    }

    if ($UpdateOnlyMissingInReplacementTable)
    { $Pages = Compare-Object -ReferenceObject $ReplacementTable -DifferenceObject $Pages | Where-Object SideIndicator -eq '=>' | Select-Object -Expand InputObject }

    Write-Verbose "$($Pages.Count) pages will be purged."

    $Parameters       = @{
      JSON            = $JSON
    }

    if ($Random)
    { $Pages = $Pages | Sort-Object { Get-Random } }

    ForEach ($Page in $Pages)
    { $ArrPSCustomObject += Update-MWPage -ID $Page.ID -Force }
  }

  End
  {
    return $ArrPSCustomObject
  }
}
#endregion

#region Update-MWPage
function Update-MWPage
{
  <#
  .SYNOPSIS
    Purges the cache for the specified pages.

  .DESCRIPTION
    Supports purging the cache for the specified pages through either
    the regular method or as an empty edit (using the -Force switch)
    which can affect deeper backend values (e.g. extensions) in a way that
    a normal purge might not.

  .PARAMETER Name
    String array of page names to purge. Cannot be used alongside the -ID parameter.

  .PARAMETER ID
    Int array of page IDs to purge. Cannot be used alongside the -Name parameter.

  .PARAMETER ForceLinkUpdate
    Update the links tables and do other secondary data updates.

  .PARAMETER ForceRecursiveLinkUpdate
    Update the links tables and do other secondary data updates,
    and update the links tables for any page that uses this page as a template.

  .PARAMETER Force
    Forces a deeper update by performing an empty edit on the page.
    
  .INPUTS
    Name (System.String) of the page to edit. Cannot be used alongside the -ID parameter.

  .INPUTS
    ID (System.UInt32) of the page to edit. Cannot be used alongside the -Name parameter.

  .OUTPUTS
    Array of PSObject holding the purge result of the given pages.
  #>
  [CmdletBinding(DefaultParameterSetName = 'PageName')]
  param (
    <#
      Core parameters
    #>
    [Parameter(Mandatory, ValueFromPipelineByPropertyName, ParameterSetName = 'PageName', Position=0)]
    [ValidateNotNullOrEmpty()]
    [Alias('Title', 'Identity', 'PageName')]
    [string[]]$Name,

    [Parameter(Mandatory, ValueFromPipelineByPropertyName, ParameterSetName = 'PageID', Position=0)]
    [Alias('PageID')]
    [uint32[]]$ID,

    [switch]$ForceLinkUpdate,
    [switch]$ForceRecursiveLinkUpdate,

    # Use Set-MWPage to perform a deeper refresh by forcing a null commit on the page
    [Alias('NullEdit')]
    [switch]$Force,

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

    [String[]]$PagesFull = @()
    
    if ($Name)
    { $PagesFull = $Name }

    if ($ID)
    { $PagesFull = $ID }

    $Max = 1
    if ($null -ne $PagesFull.Count)
    { $Max = $PagesFull.Count }

    # -Force aka perform a null edit
    if ($Force)
    {
      Write-Verbose "[Update-MWPage] Performing null edits..."

      $RateLimit = if ($script:Cache.UserInfo.RateLimits.Edit.User)
                      {$script:Cache.UserInfo.RateLimits.Edit.User}
                 else {$script:Cache.UserInfo.RateLimits.Edit.IP  }

      ForEach ($Page in $PagesFull)
      {
        if ($Name)
        { $Response = Set-MWPage -Name $Page -Content "" -Summary "" -Append -Bot -NoCreate -JSON -WarningAction:SilentlyContinue }
        else
        { $Response = Set-MWPage   -ID $Page -Content "" -Summary "" -Append -Bot -NoCreate -JSON -WarningAction:SilentlyContinue }

        if ($Response)
        {
          $ArrJSON += $Response

          $ObjectProperties = [ordered]@{
            Namespace = (Get-MWNamespace -NamespaceName (($Response.edit.title -split ':')[0])).Name
            Name      = $null
            ID        = $null
            Purged    = ($null -ne $Response.edit.result -and $Response.edit.result -eq 'Success')
          }

          if ($Name)
          { $ObjectProperties.Name = $Page }
          else
          { $ObjectProperties.ID   = $Page }

          if ($null -ne $Response.edit.title)
          { $ObjectProperties.Name = $Response.edit.title }

          if ($null -ne $Response.edit.pageid)
          { $ObjectProperties.ID   = $Response.edit.pageid }

          if ($null -ne $Response.errors.code -and $Response.errors.code -eq 'missingtitle')
          { $ObjectProperties.Missing = $true }

          $ArrPSCustomObject += New-Object PSObject -Property $ObjectProperties
        }
      }
    }
    
    # Regular page purge
    else
    {
      $Body = [ordered]@{
        action    = 'purge'
        redirects = $true # Omit if false
      }

      if ($ForceLinkUpdate)
      { $Body.forcelinkupdate = $true } # Omit if false

      if ($ForceRecursiveLinkUpdate)
      { $Body.forcerecursivelinkupdate = $true } # Omit if false

      # Purge rate limits
      $RateLimit = if ($script:Cache.UserInfo.RateLimits.Purge.User)
                      {$script:Cache.UserInfo.RateLimits.Purge.User}
                 else {$script:Cache.UserInfo.RateLimits.Purge.IP  }

      $Offset = 0
      do
      {
        $PagesLimited = @()

        for ($i = $Offset; $i -lt ($Offset + $RateLimit.Hits) -and $i -lt $Max; $i++)
        { $PagesLimited += $PagesFull[$i] }

        if ($Name)
        { $Body.titles  = ($PagesLimited -join '|') }
        else
        { $Body.pageids = ($PagesLimited -join '|') }

        Write-Verbose "[Update-MWPage] Sending payload: $($PagesLimited -join '|')"

        $Response = Invoke-MWApiRequest -Body $Body -Method POST -RateLimit $RateLimit.Seconds

        if ($Response)
        {
          $ArrJSON += $Response

          ForEach ($Page in $Response.purge)
          {
            $ObjectProperties = [ordered]@{
              Namespace = (Get-MWNamespace -NamespaceID $Page.ns).Name
              Name      = $null
              ID        = $null
              Purged    = ($null -ne $Page.purged)
            }

            if ($Page.title)
            { $ObjectProperties.Name = $Page.title }
            else
            { $ObjectProperties.ID   = $Page.id }

            if ($null -ne $Page.missing)
            {
              $ObjectProperties.Missing = $true

              Write-Warning "The page '$($Page.title)$($Page.pageid)' does not exist."
            }

            if ($ForceLinkUpdate -or $ForceRecursiveLinkUpdate)
            { $ObjectProperties.LinkUpdated = ($null -ne $Page.linkupdate) }

            $ArrPSCustomObject += New-Object PSObject -Property $ObjectProperties
          }
        }

        $Offset += $RateLimit.Hits
      } while ($Offset -lt $Max)
    }
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