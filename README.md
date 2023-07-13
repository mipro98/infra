# Infra

## Quick start

1. Clone the repo.
2. Run `./git-init.sh`
3. Deploy (see below)


Deploy everything:
```bash
make deploy
```

Deploy only docker-compose changes:
```bash
make docker-compose
```

Deploy only system changes:
```bash
make system
```


## Ansible-Vault

This repo uses ansible-vault to encrypt secret veriables used by ansible (passwords, domain names, etc.). This affects the file `vars/vault.yml`. The password for the encryption is obtained by [bitwarden-cli](https://github.com/bitwarden/cli) in the script `vault-pass.sh`. Therefore you can encrypt and decrypt by just entering your bitwarden master password.

**Always remember to encrypt the vault before commiting! Encrypt / decrypt with `make encrypt` / `make decrypt`** (so you don't have to use the slightly longer `ansible-vault` command).

**Also, absolutely run the script `git-init.sh` after cloning to install a pre-commit hook which prevents committing the unencrypted vault!**


## Why no roles?

To keep things simple, I chose not to use roles (for now) since that would mean a much more nested and constrained folder structure. Since I only have two basic "groups" of tasks I just `import` them in my `run.yml` main playbook and all the tasks can share folders for files/templates, variables and handlers without having to create seperate per-role folders for them.