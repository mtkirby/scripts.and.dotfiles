" 20261006 Kirby
"
"
" --- VISUALS & WHITESPACE ---
"set list                    " Show hidden characters 
" Set visible characters for tabs, EOL, etc 
"set listchars=tab:→\ ,eol:↲,nbsp:␣,trail:•,extends:⟩,precedes:⟨ 

set background=dark
if has("termguicolors")
    set termguicolors
endif

" --- SCRIPTABLE SETTINGS (Shielded against E319) ---
if has("eval")
    " Netrw (File Browser) Settings
	" :Lex to activate left file explorer
	" ctrl-w h j k l to move to different windows
    let g:netrw_banner=0       " Disable banner 
    let g:netrw_liststyle=3    " Tree view 
    let g:netrw_browse_split=4 " Open in previous window 
    let g:netrw_altv=1         " Open splits to the right 
    let g:netrw_winsize=25     " Set window size 
    let g:loaded_sql_completion=1 " Disable SQLComplete 

    " Catppuccin Theme Check
    " Only applies the colorscheme if the plugin is detected
    " mkdir -p ~/.vim/pack/plugins/start
    " cd ~/.vim/pack/plugins/start
    " git clone https://github.com/catppuccin/vim.git catppuccin
    "if filereadable(expand("~/.vim/pack/plugins/start/catppuccin/autoload/airline/themes/catppuccin_macchiato.vim")) || exists('g:loaded_catppuccin')
    "    colorscheme catppuccin_macchiato
    "endif

    " Syntastic (Only runs if the plugin is installed)
    if exists('g:loaded_syntastic_plugin') || filereadable(expand('~/.vim/bundle/syntastic/plugin/syntastic.vim'))
        let g:syntastic_always_populate_loc_list = 1
        let g:syntastic_auto_loc_list = 1
        let g:syntastic_check_on_open = 1
        let g:syntastic_check_on_wq = 1
        let g:syntastic_enable_signs = 1
        let g:syntastic_auto_jump = 1
        let g:syntastic_html_checkers = []
    endif
endif

" --- STATUS LINE ---
" Status bar includes file type, errors, and cursor position 
""" set statusline=%F\ [%Y]\ %m\ %r\ %h\ %w
""" set statusline+=%=
""" if exists('*SyntasticStatuslineFlag')
    """ set statusline+=%#warningmsg#%{SyntasticStatuslineFlag()}%*
""" endif
""" set statusline+=\ %p%%\ [%l/%L]

" Create a function to show the mode in the statusline
set statusline=
set statusline+=%#PmenuSel#            " Change color for the mode
set statusline+=\ %{mode()}\           " Display current mode
set statusline+=%#CursorLine#          " Switch color
set statusline+=\ %F                   " Full path to the file 
set statusline+=\ %m%r%h%w             " Modified, Read-only, Help, Preview flags 
set statusline+=%=                     " Right-align separator 
set statusline+=%#warningmsg#          " Highlight for errors
if exists('*SyntasticStatuslineFlag')
    set statusline+=%{SyntasticStatuslineFlag()} " Syntastic errors 
endif
set statusline+=%*                     " Reset highlighting 
set statusline+=\ %Y\                  " Filetype 
set statusline+=\ %{&fileencoding?&fileencoding:&encoding} " File encoding
set statusline+=\ [%p%%]               " Percentage through file 
set statusline+=\ %l:%c/%L             " Line:Column position


" --- SESSION MANAGEMENT ---
" Restores your open files and layout next time you launch Vim 
augroup AutoSaveSession
  autocmd!
  autocmd VimLeave * mksession! ~/.vim_session.vim
augroup END

" --- GENERAL SETTINGS ---
set nocompatible            " Use extended function of vim 
set backspace=2             " Allow backspacing over indent 
set history=1000            " Remember more commands
filetype indent plugin on   " Enable filetype detection and plugins 
if has("syntax")
    syntax on               " Enable syntax highlighting 
endif
set paste
set undofile
set undodir=~/.vim/undo/
set wildmenu                " better cmdline completion
set wildmode=list:longest,full 
set paste

" --- UI & VIEWPORT ---
set nu                      " Show line numbers 
set cursorline              " Highlight the current line
highlight CursorLine cterm=underline gui=underline ctermbg=NONE guibg=NONE
set lazyredraw              " Don't redraw screen while executing macros 
set ttyfast                 " Speed up rendering in terminal 
set showmatch               " Highlight parentheses 
set laststatus=2            " Always show status bar

" --- SCROLLING & WRAPPING ---
set scrolloff=5             " Start scrolling 5 lines from edge 
set sidescrolloff=5         " Horizontal scrolloff 
set wrap                    " Enable line wrapping 
set linebreak               " Don't break words in middle 
set breakindent             " Wrapped lines match indentation 
set breakindentopt=shift:0  " Indent wrapped lines by 0 extra spaces 
set showbreak=↪\            " Visual indicator for wrapped lines 

" --- SEARCHING ---
set hlsearch                " Highlight search results 
set incsearch               " Incremental search 
set ignorecase              " Ignore case in search... 
set smartcase               " ...unless capital letters are used 
nnoremap <silent> <C-l> :nohlsearch<CR> " Ctrl-l clears highlighting 

" --- TABS & INDENTATION ---
set autoindent              " Copy indent from current line 
set smartindent             " Smart autoindenting 
set cindent                 " C-style indents
set shiftwidth=4            " Size of an indent 
set tabstop=4               " Visual tab size 
set softtabstop=4           " Tab key size 
" Force expandtab even if a filetype plugin tries to disable it
autocmd FileType * setlocal expandtab
set expandtab               " Use spaces instead of tabs 

" F2 - toggle paste mode
nnoremap <F2> :set paste!<CR>

" F3 - toggle line numbers
nnoremap <F3> :set number!<CR>

" F4 - toggle relative line numbers
nnoremap <F4> :set relativenumber!<CR>

" F5 - reload current file
nnoremap <F5> :edit!<CR>

" F6 - toggle search highlighting
nnoremap <F6> :set hlsearch!<CR>

" F7 - toggle spellcheck
nnoremap <F7> :set spell!<CR>

" F8 - toggle list/invisible characters
nnoremap <F8> :set list!<CR>

" F9 - toggle wrap
nnoremap <F9> :set wrap!<CR>

" F10 - toggle cursor line
nnoremap <F10> :set cursorline!<CR>

" Clear current search highlighting
nnoremap <F11> :nohlsearch<CR>

