Function Test-GitOpsDrift {
    param(
        [ValidateScript( {
                Test-Path $_ -PathType Container
            })]
        [Parameter()]
        [String]
        $Build = $env:TEMP,

        [ValidateScript( {
                Test-Path $_ -PathType Container
            })]
        [Parameter(Mandatory = $true)]
        [String]
        $Source,

        [Parameter(Mandatory = $true)]
        [String]
        $Destination,

        [Parameter()]
        [System.Management.Automation.Runspaces.PSSession]
        $ToSession,

        [Parameter()]
        [String]
        $GitTag,

        [Parameter()]
        [Regex]
        $Exclude = '^.*\.md$',

        [Parameter()]
        [String]
        $TemplateExtension = ".eps1",

        [Parameter()]
        [String]
        $SpectoCommon = ".specto",

        [Parameter()]
        [String]
        $SpectoSignature
    )
    Process {
        $InvCmdParams = @{}
        If ($PSBoundParameters['ToSession']) {
            $InvCmdParams.Session = $ToSession
        }
        If (-not $(Invoke-Command -ScriptBlock { Test-Path $using:Destination } @InvCmdParams)) {
            Write-Error "$Destination directory not found."
        }
        $SourceDirectory = Get-Item $Source
        $BuildDirectory = Get-Item $Build
        $DestinationDirectory = Invoke-Command -ScriptBlock { Get-Item $using:Destination } @InvCmdParams
        Push-Location $SourceDirectory
        Try {
            $Files = @{}
            If ($PSBoundParameters['GitTag']) {
                $GitStatusCmdOutput = git diff --name-status $GitTag HEAD
            }
            Else {
                $GitStatusCmdOutput = git diff --name-status HEAD^ HEAD
            }
            ForEach ($Line in $GitStatusCmdOutput) {
                $GitStatusArray = $Line.Split("`t")
                If ($GitStatusArray.Count -eq 3) {
                    $GitSrcFile = ([System.IO.Path]::GetFullPath($GitStatusArray[2])).Replace("$($env:PWD.path)", "")
                    $Files["$GitSrcFile"] = @{
                        FromFile  = ([System.IO.Path]::GetFullPath($GitStatusArray[1])).Replace("$($env:PWD.path)", "")
                        GitStatus = $GitStatusArray[0]
                        Checked   = $false
                    }
                }
                ElseIf ($GitStatusArray.Count -eq 2) {
                    $GitSrcFile = ([System.IO.Path]::GetFullPath($GitStatusArray[1])).Replace("$($env:PWD.path)", "")
                    $Files["$GitSrcFile"] = @{
                        FromFile  = $GitSrcFile
                        GitStatus = $GitStatusArray[0]
                        Checked   = $false
                    }
                }
            }
            Write-Debug "$($Files | ConvertTo-Json -Depth 100)"
            ForEach ($SourceFile in $(Get-ChildItem $SourceDirectory.FullName -Recurse -File)) {
                $SourceFileRelPath = $SourceFile.FullName.Replace($SourceDirectory.FullName, "")
                $BuildFile = @{
                    FullName  = Join-Path -Path $BuildDirectory.FullName -ChildPath $SourceFile.FullName.Replace($SourceDirectory.FullName, "")
                    Directory = Join-Path -Path $BuildDirectory.FullName -ChildPath $SourceFile.Directory.FullName.Replace($SourceDirectory.FullName, "")
                }
                $DestinationFile = @{
                    FullName  = Join-Path -Path $DestinationDirectory.FullName -ChildPath $SourceFile.FullName.Replace($SourceDirectory.FullName, "")
                    Directory = Join-Path -Path $DestinationDirectory.FullName -ChildPath $SourceFile.Directory.FullName.Replace($SourceDirectory.FullName, "")
                }
                If ($SourceFile.Name.EndsWith($TemplateExtension)) {
                    $BuildFile.FullName = $BuildFile.FullName.Replace($TemplateExtension, "")
                    $DestinationFile.FullName = $DestinationFile.FullName.Replace($TemplateExtension, "")
                }
                ElseIf ($SourceFile.Name.Contains($SpectoCommon)) {
                    If ($SpectoSignature -and ($SourceFile.Name.EndsWith($SpectoSignature))) {
                        $BuildFile.FullName = $BuildFile.FullName.Replace($SpectoCommon, "").Replace($SpectoSignature, "")
                        $DestinationFile.FullName = $DestinationFile.FullName.Replace($SpectoCommon, "").Replace($SpectoSignature, "")
                    }
                }
                $BuildFileHash = Get-FileHash $BuildFile.FullName
                $DestinationFileHash = Invoke-Command -ScriptBlock { Get-FileHash $using:DestinationFile.FullName -ErrorAction SilentlyContinue } @InvCmdParams
                $DestinationFileRelPath = $DestinationFile.FullName.Replace($DestinationDirectory.FullName, "")
                Switch ($Files["$SourceFileRelPath"].GitStatus) {
                    'A' {
                        # addition of a file
                        Write-Verbose "$SourceFileRelPath was Added since last build, $($DestinationDirectory.FullName) Hash should be null."
                        If ($null -ne $DestinationFileHash) {
                            Write-Warning "$SourceFileRelPath was Added but $DestinationFileRelPath already exists in $($DestinationDirectory.FullName)"
                        }
                        $Files["$SourceFileRelPath"].Checked = $true
                        Break
                    }
                    'C' {
                        # copy of a file into a new one
                        Write-Warning "$SourceFileRelPath has as a status of 'C'. This case is not yet handled."
                        $Files["$SourceFileRelPath"].Checked = $true
                        Break
                    }
                    'D' {
                        # deletion of a file
                        Write-Warning "$SourceFileRelPath was Deleted since last build, $($DestinationDirectory.FullName) will be left alone, consider deleting."
                        $Files["$SourceFileRelPath"].Checked = $true
                        Break
                    }
                    'M' {
                        # modification of the contents or mode of a file
                        Write-Verbose "$SourceFileRelPath was Modified since last build, $($DestinationFile.Fullname) should be different than Source and overwritten."
                        If ($null -ne $DestinationFileHash) {
                            Write-Warning "$SourceFileRelPath was Modified but $($DestinationFile.FullName) was not found."
                        }
                        ElseIf ($BuildFileHash.Hash -eq $DestinationFileHash.Hash) {
                            Write-Warning "$SourceFileRelPath was Modified but $($DestinationFile.Fullname) matches the hash of the $($BuildFile.FullName) file. File may have already been deployed."
                        }
                        $Files["$SourceFileRelPath"].Checked = $true
                        Break
                    }
                    'R' {
                        # renaming of a file
                        $fromFile = $Files["$SourceFileRelPath"].FromFile
                        Write-Verbose "$SourceFileRelPath has been renamed from $fromFile. $($DestinationFile.Fullname) should not exist. Any file generated from $fromFile should be considered for deletion."
                        If ($null -ne $DestinationFileHash) {
                            Write-Warning "$SourceFileRelPath was renamed from $fromFile, but $DestinationFileRelPath already exists in $($DestinationDirectory.FullName)"
                        }
                        Write-Warning "$SourceFileRelPath was renamed from $fromFile, consider deleting any file that was generated from $fromFile."
                        $Files["$SourceFileRelPath"].Checked = $true
                        Break
                    }
                    'T' {
                        # change in the type of the file
                        Write-Warning "$SourceFileRelPath has as a status of 'T'. This case is not yet handled."
                        $Files["$SourceFileRelPath"].Checked = $true
                        Break
                    }
                    'U' {
                        # file is unmerged
                        Write-Error "$SourceFileRelPath has as a status of 'U'. All files shoudl be merged at this point."
                        $Files["$SourceFileRelPath"].Checked = $true
                        Break
                    }
                    'X' {
                        # "unknown" change type (bug)
                        Write-Error "$SourceFileRelPath has as a status of 'X'. Git 'X' is a unkown change type... there may be a bug."
                        $Files["$SourceFileRelPath"].Checked = $true
                        Break
                    }
                    Default {
                        # no git status, no change expected
                        Write-Verbose "$SourceFileRelPath has no changes since the last build. $($BuildFile.FullName) should match $($DestinationFile.FullName)."
                        If ($null -eq $DestinationFileHash) {
                            Write-Warning "$SourceFileRelPath has no changes since the last build. $($DesinationFile.FullName) was not found."
                        }
                        ElseIf ($($DestinationFileHash.Hash) -ne $($BuildFileHash.Hash)) {
                            Write-Warning "$SourceFileRelPath has no changes since the last build. $($BuildFile.FullName) does not match $($DestinationFile.FullName)."
                        }
                        Break
                    }
                }
            }
            ForEach ($File in $($Files.GetEnumerator() | Where-Object checked -eq $false)) {
                # check all other files, should be the deleted files
                Switch ($Files["$SourceFileRelPath"].GitStatus) {
                    'D' {
                        Write-Warning "$SourceFileRelPath was deleted. Consider deleting $($DestinationFile.FullName)."
                        $Files["$SourceFileRelPath"].Checked = $true
                        Break
                    }
                    Default {
                        $gitStatus = $Files["$SourceFileRelPath"].GitStatus
                        $checked = $Files["$SourceFileRelPath"].Checked
                        Write-Warning "$SourceFileRelPath has a git status of $gitStatus and has a checked of $checked. This should have already been addressed."
                    }
                }
            }
        }
        Finally {
            Pop-Location
        }
    }
}