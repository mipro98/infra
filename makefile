deploy:
	ansible-playbook run.yml

containers:
	ansible-playbook run.yml -t compose

system:
	ansible-playbook run.yml -t system

maintenance:
	ansible-playbook run.yml -t maintenance

script:
	ansible-playbook run.yml -t script

# -----------------

decrypt:
	ansible-vault decrypt vars/vault.yml

encrypt:
	ansible-vault encrypt vars/vault.yml