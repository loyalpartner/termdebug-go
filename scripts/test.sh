vim -Es --not-a-term -Nu <(cat << EOF
filetype off
set rtp+=~/vim-dev/plug.nvim/plugged/vader.vim
set rtp+=~/vim-dev/plug.nvim/plugged/termdebug-go
filetype plugin indent on
syntax enable
EOF
) -c "Vader! test/*"
