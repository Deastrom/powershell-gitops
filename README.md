# powershell-gitops
A series of scripts for use in CI/CD to build, stage, and check config files using concepts inspired from Ansible.

## Goal

The goal of this repository is to provide a series of scripts that support the transformation of generic files into files specific to a system.

## Concept

The idea of managing configurations comes down to managing the files and scripts needed to configure an application across different systems.  The differences between these systems tends to be an issue for many Administrators.  I really like the Ansible approach to many of the issues I have run into, but the heft of Ansible itself can be daunting to System Administrators.  So instead we pick some core pricipals of file management in Ansible and implement them in Powershell.  I will attempt to do this using as few dependencies as possible, relying primarily on modules provided with the distribution of Powershell Core.

## File Types

In my experience there are three kinds of files that are managed in a source repo.

1. Templates

    These files are Jinja2 files in Ansible.  In Powershell we use a module called [EPS](https://github.com/straightdave/eps) which allows us to embed Powershell code into template files.

    These are identified in the scripts by the extension of `.eps1`.  For example, `test.txt.eps1` would be processed through the script and come out on the other end as `test.txt`.

2. Specific To a System (specto)

    There are files that are specific to a system, but still need captured.  These are not secret files.  They are files that have too many differences to create Templates from, but differ from system to system.

    These are identified with a combination of extensions looking like `.specto.<signature>` where *signature* is specific to the system you wish to run the script against.  For example, `test.txt.specto.app-db-01-test` would copy to `test.txt` only when the script is run for the system *app-db-01-test*.

3. Normal File

    Files that do not fall into the above categories will simply be copied.

4. Secret Files (!Planned)

    For now, use an independent secrets management method.

    ~~These files contain secrets and need to be encrypted.  This file type should work in combination with the other file types meaning that a template or specto file can be secrets.  I think I'll try to use Secure-String encryption with a generated key.~~

    ~~These are identified by the extension of `.secret`.~~

    **NOTE**

    I could use SecureString with -SecureKey and require a 16 character password.

    Suggested password generator and settings results in 105bits of blind entropy.

    https://xkpasswd.net

    ```json
    {
        "num_words": 3,
        "word_length_min": 4,
        "word_length_max": 4,
        "case_transform": "RANDOM",
        "separator_character": "RANDOM",
        "separator_alphabet": ["!","@","$","%","^","&","*","-","_","+","=",":","|","~","?","/",".",";"],
        "padding_digits_before": 0,
        "padding_digits_after": 1,
        "padding_type": "NONE",
        "random_increment": "AUTO"
    }
    ```

## Intent Detection

We can imply file intent based on the git diff of the last time the repository was built.  To identify the last time it was built, we'll use a tag.

1. File Added

    In this situation, we don't expect the file to be in the destination system.

    We should copy the file over to the target system, creating it.

2. File Modified

    In this situation, we expect the file to exist in the destination system and does not match the file that will be generated, but should match the file that was generated from last built.

    We should copy the file over to the target system, changing it.

3. File Deleted

    In this situation, we expect the file to exist in the destination system and should match the file that was generated from last built.

    We should delete the target file from the destination.

We should throw errors when the change is destructive and provide a parameter for only warning on intent.

## Return Object

The returned powershell object should contain the following for each file in the source directory.

output of *gitops-build.ps1* in psd format, actual export will be clixml format.

```powershell
@(
    @{
        operation = "eps" # One of the following: eps, specto, copy
        source = @{
            # Attributes from Get-Item plus...
            DiffState = "Modified" # One of the following: Added, Modified, or Deleted
            Hash = # Result from Get-FileHash
        }
        epsDiff = # Diff between source and staged if the operation is eps and not secret
        currentBuild = @{
            # Attributes from Get-Item plus...
            Hash = # Result from Get-FileHash
        }
    }
)
```

output of *gitops-test.ps1* in psd format, actual export will be in clixml format.

```powershell
@(
    @{
        intent = # one of Create, Update, or Delete
        currentBuild = @{
            # Attributes from Get-Item plus...
            Hash = # Result from Get-FileHash
        }
        lastBuild = @{
            # Attributes from Get-Item plus...
            Hash = # Result from Get-FileHash
        }
        onSystem = @{
            # Attributes from Get-Item plus...
            Hash = # Result from Get-FileHash
        }
    }
)
```

output of *gitops-deploy.ps1* is yet to be determined