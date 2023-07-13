deploy:
	ansible-playbook run.yml

docker-compose:
	ansible-playbook run.yml -t compose

system:
	ansible-playbook run.yml -t system

decrypt:
	ansible-vault decrypt vars/vault.yml

encrypt:
	ansible-vault encrypt vars/vault.yml