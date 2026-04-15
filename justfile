switch:
  sudo nixos-rebuild switch --flake .#${HOSTNAME}

deploy-hetzner configuration ip user="fjolne":
  LD_LIBRARY_PATH= nix run github:numtide/nixos-anywhere/1.9.0 -- --build-on-remote root@{{ip}} --flake .#{{configuration}}
  ssh-keygen -f ~/.ssh/known_hosts -R {{ip}}
  sleep 120
  ssh -o StrictHostKeyChecking=no {{user}}@{{ip}} true
  rsync -av --filter=':- .gitignore' $(realpath .) {{user}}@{{ip}}:./
  just post-deploy {{user}}

post-deploy user:
  #!/usr/bin/env bash
  cat <<EOF
  Run these commands on a deployed machine:
  passwd
  cd && git clone https://github.com/fjolne/dotfiles && cd ~/dotfiles && just home-switch .#{{user}}@nixos
  npm install -g @openai/codex
  EOF
