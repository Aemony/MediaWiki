# MediaWiki
This is a PowerShell module for interfacing with a MediaWiki API endpoint that I have worked at
on and off occasionally over the last couple of years. It was initially created to assist me in
performing various maintenance tasks for the [PCGamingWiki](https://www.pcgamingwiki.com/) (PCGW) community project.

While other more powerful alternatives do exists (e.g. pymediawiki) I personally prefer working
with and use PowerShell as that is what I also use professionally, and I feel that a well-defined
PowerShell module manages to expose APIs and endpoints to regular users even on normal Windows
installations without requiring any major dependencies to be installed.

Note that due to its focus on the PCGamingWiki and its outdated version of MediaWiki, the module
might not support all options/flags exposed in later versions. While most of the development has
been performed by consulting the official MediaWiki Action API documentation, incompatible stuff
have been disabled in favor of making it work more flawlessly with PCGW.

Due to its rather early stage of development, the module continues to see frequent and massive
changes throughout its code as I learn, rethink, and redesign components here and there.

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

4. Once having established a connection to an API endpoint, use one of these commands to interface with it:

 * `Connect-MWSession` - Connect to an API endpoint.
 * `ConvertTo-MWParsedOutput` - Limited interface for [action=parse](https://www.mediawiki.org/wiki/API:Parsing_wikitext) to get the endpoint to return with the parsed output of a given wikitext.
 * `Disconnect-MWSession` - Disconnect from the API endpoint.
 * `Find-MWImage` - Interface for [list=allimages](https://www.mediawiki.org/wiki/API:Allimages) to list all image files.
 * `Find-MWOrphanedRedirect` - Helper to generate a list of all orphaned redirects. Takes a long time with ~50k pages, so be warned. :)
 * `Find-MWPage` - Interface for [list=allpages](https://www.mediawiki.org/wiki/API:Allpages) to list all pages.
 * `Find-MWRedirect` - Variant of `Find-MWPage` to list all redirect pages.
 * `Get-MWBackLink` - Interface for [list=backlinks](https://www.mediawiki.org/wiki/API:Backlinks) to list all pages which links to the given page.
 * `Get-MWCargoQuery` - **Requires [Extension:Cargo](https://www.mediawiki.org/wiki/Extension:Cargo).** Performs a Cargo query.
 * `Get-MWCategoryMember` - Interface for [list=categorymembers](https://www.mediawiki.org/wiki/API:Backlinks) to list all pages in the given category.
 * `Get-MWDuplicateFile` - Uses the *allimages* generator to retrieve duplicates of the given image, if any exists.
 * `Get-MWEmbeddedIn` - Interface for [list=embeddedin](https://www.mediawiki.org/wiki/API:Embeddedin) to list all other pages the given page is embedded in.
 * `Get-MWGroupMember` - Alias for `Get-MWCategoryMember`. *Might change!*
 * `Get-MWImageInfo` - Interface for [prop=imageinfo](https://www.mediawiki.org/wiki/API:Imageinfo) to list file information and upload history for the given image.
 * `Get-MWImageUsage` - Interface for [list=imageusage](https://www.mediawiki.org/wiki/API:Imageusage) to list all pages that use the given image.
 * `Get-MWRecentChanges` - Interface for [list=recentchanges](https://www.mediawiki.org/wiki/API:RecentChanges) to list all recent changes on the site.
 * `Get-MWLink` - Uses the *links* generator to retrieve all internal wiki links of the given page.
 * `Get-MWNamespace` - Retrieves all registered namespaces on the site.
 * `Get-MWNamespacePage` - Variant of `Find-MWPage` to list all pages in the given namespace.
 * `Get-MWPage` - Interface for [action=parse](https://www.mediawiki.org/wiki/API:Parsing_wikitext) to retrieve the wikitext of the given page.
 * `Get-MWPageInfo` - Interface for [prop=info](https://www.mediawiki.org/wiki/API:Info) to get properties for the given page.
 * `Get-MWProtectionLevel` - Retrieves all registered protection levels on the site.
 * `Get-MWProtectionType` - Retrieves all registered protection types on the site.
 * `Get-MWSiteInfo` - Interface for [meta=siteinfo](https://www.mediawiki.org/wiki/API:Siteinfo) to retrieve general information about the site. 
 * `Get-MWTranscludedIn` - Alias for `Get-MWEmbeddedIn`.
 * `Get-MWUserInfo` - Interface for [meta=userinfo](https://www.mediawiki.org/wiki/API:Userinfo) to retrieve general information about the current user. 
 * `Invoke-MWApiContinueRequest` - Useful helper that automatically handles continuing API requests when there are more results available.
 * `Invoke-MWApiRequest` - Handles the core aspects of performing an API request.
 * `Move-MWPage` - Interface for [action=move](https://www.mediawiki.org/wiki/API:Move) to move a page.
 * `New-MWPage` - Variant of `Set-MWPage` to create a new page.
 * `Remove-MWPage` - Interface for [action=delete](https://www.mediawiki.org/wiki/API:Delete) to delete a page.
 * `Search-MWPage` - Interface for [list=search](https://www.mediawiki.org/wiki/API:Search) to perform a full text search on the site.
 * `Set-MWPage` - Interface for [action=edit](https://www.mediawiki.org/wiki/API:Edit) to edit a page.
 * `Update-MWPage` - Weird hack that is both an interface for [action=purge](https://www.mediawiki.org/wiki/API:Purge) but also a variant of `Set-MWPage` when used with -NullEdit.
  * A "null edit" is what the PCGW community ended up calling performing an edit where no actual content is changed. This type of change can at times trigger backend refreshes (e.g. extensions such as Cargo) that otherwise would not be affected by a normal purge (even ones with ForceLinkUpdate and ForceRecursiveLinkUpdate enforced).
 * `Watch-MWPage` - Not implemented. Will probably end up watching or unwatching a page maybe?

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
