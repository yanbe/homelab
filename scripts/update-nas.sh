# 毎回 update しない！
# アップデートしたい時だけ手動で `nix flake update` を叩く
# sudo nix flake update --extra-experimental-features 'nix-command flakes'

eval $(ssh-agent)
ssh-add ~/.ssh/ssh_ca_key
nixos-rebuild switch --flake .#nas --target-host root@nas.local
