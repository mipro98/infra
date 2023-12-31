#!/bin/bash
# sets up a pre-commit hook to ensure that vault.yaml is encrypted
#
# credit goes to Alex Kretzschmar @ironicbadger and nick busey from homelabos for this script
# https://github.com/ironicbadger/infra/blob/master/git-init.sh
# https://gitlab.com/NickBusey/HomelabOS/-/issues/355



if [ -d .git/ ]; then
    rm .git/hooks/pre-commit
    cat <<EOT >> .git/hooks/pre-commit
    if ( git show :vars/vault.yml | grep -q "\$ANSIBLE_VAULT;" ); then
        echo -e "\033[38;5;108mVault Encrypted. Safe to commit.\033[0m"
    else
        echo -e "\033[38;5;208mVault not encrypted! Run 'make encrypt' and try again.\033[0m"
        exit 1
    fi
EOT

fi

chmod +x .git/hooks/pre-commit