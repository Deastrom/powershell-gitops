Function Deploy-GitOpsBuild {
    <#
    .SYNOPSIS
    Compares each file in the build directory with its representation in the
    destination directory and copies the build directory file over if the
    destination file does not match.
    
    .DESCRIPTION
    The 'Deploy-GitOpsBuild' function check each file in the build directory
    against it's file in the destination directory.  It checks for the file hash
    of the Destination file.  If the file is there and the hash matches the Build
    hash, the file is not copied.  Otherwise, the file is copied.

    .PARAMETER Build
    The Directory that will be parsed and copied from.

    .PARAMETER Destination
    The Directory that will be parsed and copied to.

    .PARAMETER Source
    Not Used in this function. Added for splatting purposes.

    .INPUTS
    None.  No values are to be piped into this function.

    .OUTPUTs
    None
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateScript( {
                Test-Path $_ -PathType Container
            })]
        [String]
        $Build,
        [ValidateScript( {
                Test-Path $_ -IsValid -PathType Container
            })]
        [String]
        $Destination,
        [String]
        $Source
    )
    Process {
        $BuildDirectory = Get-Item -Path $Build
        If (-not $(Test-Path $Destination )) {
            Write-Verbose "Creating $Destination directory"
            New-Item $Destination -ItemType Directory | Write-Verbose
        }
        $DestinationDirectory = Get-Item $Destination
        ForEach ($BuildFile in $(Get-ChildItem $BuildDirectory -Recurse -File)) {
            $DestinationFile = @{
                FullName = Join-Path -Path $DestinationDirectory.FullName -ChildPath $BuildFile.FullName.Replace($BuildDirectory.FullName,"")
                Directory = Join-Path -Path $DestinationDirectory.FullName -ChildPath $BuildFile.Directory.Fullname.Replace($BuildDirectory.FullName, "")
            }
            $BuildFileHash = Get-FileHash $BuildFile
            $DestinationFileHash = Get-FileHash $DestinationFile.FullName -ErrorAction SilentlyContinue
            If ($DestinationFileHash -and ($BuildFileHash.Hash -eq $DestinationFileHash.Hash)) {
                Write-Verbose "$($DestinationFileHash.Path) hash matches $($BuildFileHash.Path) hash, not copying."
            } Else {
                Write-Verbose "Copying $($BuildFile.FullName) to $($DestinationFile.FullName)"
                if (-Not $(Test-Path $DestinationFile.Directory)) {
                    Write-Verbose "Creating $($DestinationFile.Directory) directory"
                    New-Item $DestinationFile.Directory -ItemType Directory | Write-Verbose
                }
                Copy-Item $BuildFile -Destination $DestinationFile.FullName
            }
        }
    }
}