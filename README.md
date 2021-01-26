# powershell-gitops
A module for use in CI/CD to build, stage, and check config files using concepts inspired from Ansible.

## Goal

The goal of this repository is to provide a module that supports the transformation of generic files into files specific to a system.

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

## Drift Detection

Hoping to be able to use git status, the source directory, the build, directory, and the destination directory to detect configuration drift.  Plan right now is to just warn about it.
