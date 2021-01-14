# powershell-gitops
A series of scripts for use in CI/CD to build, stage, and check config files using concepts inspired from Ansible.

## Goal

The goal of this repository is to provide a series of scripts that support the transformation of generic files into files specific to a system.

## Concept

The idea of managing configurations comes down to managing the files and scripts needed to configure an application across different systems.  The differences between these systems tends to be an issue for many Administrators.  I really like the Ansible approach to many of the issues I have run into, but the heft of Ansible itself can be daunting to System Administrators.  So instead we pick some core pricipals of file management in Ansible and implement them in Powershell.  I will attempt to do this using as few dependencies as possible, relying primarily on modules provided with the distribution of Powershell Core.

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

    These files contain secrets and need to be encrypted.  This file type should work in combination with the other file types meaning that a template or specto file can be secrets.  I think I'll try to use Secure-String encryption with a generated key.

    These are identified by the extension of `.secret`.