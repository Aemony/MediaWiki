# MediaWiki
This is a PowerShell module for interfacing with a MediaWiki API endpoint that I have worked at
on and off occasionally over the last couple of years. It was initially created to assist me in
performing [various maintenance tasks](https://github.com/Aemony/AemonyBot) for the [PCGamingWiki](https://www.pcgamingwiki.com/) (PCGW) community project.

A major focus of the module have been to ensure pipeline compatibility across the cmdlets.

...

While other more powerful alternatives exists (e.g. pymediawiki), I prefer working with and use
PowerShell as I like that a well-defined PowerShell module exposes APIs and datasets to regular
users and allows them to interact with the dataset without the need of any additional dependencies.

Note that due to its focus on the PCGamingWiki and its outdated version of MediaWiki, the module
might not support all options/flags added in newer versions. While most of the development has
been performed by consulting the official MediaWiki Action API documentation, incompatible stuff
have been disabled in favor of making it work more flawlessly with PCGW.

Due to its rather early stage of development, the module might see frequent and massive changes
throughout the codebase as I learn, rethink, and redesign functions or the internal components.

## Installation
*If authenticating, a [bot password](https://www.mediawiki.org/wiki/Manual:Bot_passwords) needs to be used as the module does not support OAuth.*
*Anonymous logins are of course also supported!*

1. Download or clone the repository to a local folder called `MediaWiki`.

2. Launch a new PowerShell session and import the module by using `Import-Module <path-to-the-MediaWiki-folder>` (e.g. `Import-Module .\MediaWiki`)

   * Be sure to omit any trailing backslash in the path as otherwise the command will fail.

3. Connect to a MediaWiki endpoint using one of these alternatives:

   * To establish a new connection: `Connect-MWSession`
   * To use/setup a persistent config: `Connect-MWSession -Persistent`
   * To log in anonymously as a guest: `Connect-MWSession -Guest`
   * To use a persistent config as a guest: `Connect-MWSession -Persistent -Guest`
   * To disconnect from an active session, use `Disconnect-MWSession`

4. Once a connection has been established, use one of the supported [cmdlets](#Cmdlets).

## Examples

*For more real-world examples, visit the [AemonyBot](https://github.com/Aemony/AemonyBot) repository.*

Retrieve the wikitext of a page:
```powershell
Get-MWPage 'NieR: Automata' -Wikitext
```

Add new content to the end of a specific section:
```powershell
(Get-MWPage 'NieR: Automata').Sections | Where Line -eq 'Inventory Editor' | Add-MWSection -Content "In Summer of 2038 an updated version was released with bug fixes and QoL improvements." -Summary "Added information pertaining to the 2038 update."
```

Forces a deeper cache purge of a page by performing an empty edit on it:
```powershell
Get-MWPage 'NieR: Automata' | Update-MWPage -Force
```

Performs a Cargo query to retrieve all pages using the SecuROM DRM:
```powershell
Get-MWCargoQuery -Table Availability -Where "Uses_DRM HOLDS LIKE 'SecuROM%'" -Fields 'Uses_DRM' -ResultSize Unlimited
```

Performs a deep cache purge on all SecuROM pages:
```powershell
$Pages = Get-MWCargoQuery -Table Availability -Where "Uses_DRM HOLDS LIKE 'SecuROM%'" -Fields 'Uses_DRM' -ResultSize Unlimited
$Pages | Update-MWPage -Force
```

## Cmdlets
**Pages**
* `Add-MWPage` - Add content to a page.
  * Implemented as a variant of `Set-MWPage`.
* `Get-MWPage` -  Retrieves information about a page. Use `-Wikitext` to also fetch the wikitext of the page.
  * Interface for [action=parse](https://www.mediawiki.org/wiki/API:Parsing_wikitext).
* `Get-MWPageInfo` - Retrieves additional properties of a page.
  * Interface for [prop=info](https://www.mediawiki.org/wiki/API:Info).
* `Get-MWPageLink` - Retrieve all internal wiki links of a page.
  * Uses the *links* generator.
* `Clear-MWPage` - Clears all content on the specified page.
  * Implemented as a variant of `Set-MWPage`.
* `Find-MWPage` - List all pages on the wiki.
  * Interface for [list=allpages](https://www.mediawiki.org/wiki/API:Allpages).
* `Move-MWPage` - Moves a page.
  * Interface for [action=move](https://www.mediawiki.org/wiki/API:Move).
* `New-MWPage` - Creates a new page. Implemented as a variant of `Set-MWPage`.
* `Remove-MWPage` - Deletes a page.
  * Interface for [action=delete](https://www.mediawiki.org/wiki/API:Delete).
* `Rename-MWPage` - Alias for `Move-MWPage`.
* `Search-MWPage` - Perform a full text search on the site.
  * Interface for [list=search](https://www.mediawiki.org/wiki/API:Search).
* `Set-MWPage` - Edit the contents of a page.
  * Interface for [action=edit](https://www.mediawiki.org/wiki/API:Edit).
* `Update-MWPage` - Purges the cache for a page. Use `-Force` for a deeper purge by performing an empty edit of the page.
  * An empty edit (`-Force`) can at times trigger backend refreshes (e.g. extensions such as Cargo) that otherwise would not be affected by a normal cache purge.
  * Interface for [action=purge](https://www.mediawiki.org/wiki/API:Purge). Imlemented as a variant of `Set-MWPage` when used with `-Force`.
* `Undo-MWPageEdit` - Undo specific edits of a page. Use `-Rollback` to undo all edits made by the last user to edit the page.
  * Imlemented as a variant of `Set-MWPage`. Interface for [action=rollback](https://www.mediawiki.org/wiki/API:Rollback) when used with `-Rollback`.

**Sections**
* `Add-MWSection` - Add content to a section.
  * Implemented as a variant of `Set-MWPage`.
* `Clear-MWSection` - Clear the content from a section.
  * Implemented as a variant of `Set-MWPage`.
* `Get-MWSection` - Retrieves information about a section. Use `-Wikitext` to also fetch the wikitext of the section.
  * Implemented as a variant of `Get-MWPage`.
* `Remove-MWSection` - Removes a section.
  * Implemented as a variant of `Set-MWPage`.
* `Rename-MWSection` - Changes the title/header of a section.
  * Implemented as a variant of `Set-MWPage`.
* `Set-MWSection` - Sets the content of a section.
  * Implemented as a variant of `Set-MWPage`.

**Files/Images**
* `Find-MWFile` - List all files/images.
  * Interface for [list=allimages](https://www.mediawiki.org/wiki/API:Allimages).
* `Find-MWFileDuplicate` - Find duplicates of a file/image, if any exists.
  * Uses the *allimages* generator.
* `Get-MWFileInfo` - List file information and upload history.
  * Interface for [prop=imageinfo](https://www.mediawiki.org/wiki/API:Imageinfo).
* `Get-MWFileUsage` - List all pages that use a file/image.
  * Interface for [list=imageusage](https://www.mediawiki.org/wiki/API:Imageusage).

**Links / Redirects**
* `Get-MWBackLink` - List all pages which links to a page.
  * Interface for [list=backlinks](https://www.mediawiki.org/wiki/API:Backlinks).
* `Find-MWRedirect` - Variant of `Find-MWPage` to list all redirect pages.
* `Find-MWRedirectOrphan` - Helper to generate a list of all orphaned redirects. Takes a long time with ~50k pages, so be warned. :)

**Categories**
* `Get-MWCategoryMember` - List all pages in a category.
  * Interface for [list=categorymembers](https://www.mediawiki.org/wiki/API:Categorymembers).

**Templates**
* `Get-MWEmbeddedIn` - List all other pages a page is embedded in.
  * Interface for [list=embeddedin](https://www.mediawiki.org/wiki/API:Embeddedin).
* `Get-MWTranscludedIn` - Alias for `Get-MWEmbeddedIn`.

**Namespaces**
* `Get-MWNamespace` - Retrieves all registered namespaces on the site.
* `Get-MWNamespacePage` - List all pages in a namespace.
  * Implemented as a variant of `Find-MWPage`.

**Recent Changes**
* `Get-MWRecentChanges` - List all recent changes on the site.
  * Interface for [list=recentchanges](https://www.mediawiki.org/wiki/API:RecentChanges).

**Connection**
* `Connect-MWSession` - Connect to an API endpoint.
* `Disconnect-MWSession` - Disconnect from the API endpoint.

**Site information**
* `Get-MWChangeTag` - List all recognized change tags on the site.
  * Interface for [list=tags](https://www.mediawiki.org/wiki/API:Tags).
* `Get-MWProtectionLevel` - Retrieves all registered protection levels on the site.
  * Implemented as a variant of `Get-MWSiteInfo`.
* `Get-MWProtectionType` - Retrieves all registered protection types on the site.
  * Implemented as a variant of `Get-MWSiteInfo`.
* `Get-MWSiteInfo` - Retrieve general information about the site.
  * Interface for [meta=siteinfo](https://www.mediawiki.org/wiki/API:Siteinfo).

**Users**
* `Get-MWUser` - Retrieve information about a user.
* `Get-MWCurrentUser` - Retrieve general information about the signed in user.
  * Interface for [meta=userinfo](https://www.mediawiki.org/wiki/API:Userinfo)
* `Get-MWCurrentUserPreference` - Retrieve the perferences of the current user.
  * Implemented as a variant of `Get-MWCurrentUser`.
* `Get-MWCurrentUserGroup` - Retrieve the groups the current user is a member of.
  * Implemented as a variant of `Get-MWCurrentUser`.
* `Get-MWCurrentUserRateLimit` - Retrieve the rate limits applied to the current user.
  * Implemented as a variant of `Get-MWCurrentUser`.
* `Get-MWCurrentUserRight` - Retrieve the permissions/rights of the current user.
  * Implemented as a variant of `Get-MWCurrentUser`.

**Watchlist**
* `Watch-MWPage` - Not implemented. Will probably end up watching or unwatching a page maybe?

**Extensions**
* `Get-MWCargoQuery` - Performs a query against the Cargo backend, provided [Extension:Cargo](https://www.mediawiki.org/wiki/Extension:Cargo) is installed.

**Misc**
* `ConvertTo-MWParsedOutput` - Have the site parse the input wikitext and reply with the results.
  * Limited interface for [action=parse](https://www.mediawiki.org/wiki/API:Parsing_wikitext).
* `Invoke-MWApiContinueRequest` - Useful helper that automatically handles continuing API requests when there are more results available.
* `Invoke-MWApiRequest` - Handles the core aspects of performing an API request.

## Cheat sheet
If actively working on the module and its code, I find the below one-liner to be quite helpful to reload the whole thing quickly:

* `Disconnect-MWSession; Remove-Module MediaWiki; Import-Module .\MediaWiki; Connect-MWSession -Persistent -Guest`

## Possible future To-Do's
Random personal thoughts and ideas that have come up...

* Summarizing the functions for this readme had me realize that the *Find-* / *Get-* verbs in the function names might need a rethink in some cases?
* Change `Get-MWGroupMember` to actually retrieve the users of a given group?
* Add more helpers/variants e.g. Add-/Remove- ?

## Third-party code
Third-party code is noted in the source code, with the appropriate license links.
This is a short overview of the code being used:

* https://stackoverflow.com/a/57045268
* https://github.com/abgox/ConvertFrom-JsonToHashtable
