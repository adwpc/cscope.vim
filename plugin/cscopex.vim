" vim: tabstop=2 shiftwidth=2 softtabstop=2 expandtab foldmethod=marker
"    Copyright: Copyright (C) 2012-2015 Brook Hong
"    License: The MIT License
"

if !exists('g:cscope_silent')
  let g:cscope_silent = 0
endif

if !exists('g:cscope_auto_update')
  let g:cscope_auto_update = 1
endif

if !exists('g:cscope_open_quickfix')
  let g:cscope_open_quickfix = 1
endif

if !exists('g:cscope_split_threshold')
  let g:cscope_split_threshold = 10000
endif

function! s:echo(msg)
  if g:cscope_silent == 0
    echo a:msg
  endif
endfunction


function! s:GetBufferList()
  redir =>buflist
  silent! ls
  redir END
  return buflist
endfunction

function! QuickFixToggle()
  for bufnum in map(filter(split(s:GetBufferList(), '\n'), 'v:val =~ "Quickfix"'), 'str2nr(matchstr(v:val, "\\d\\+"))')
    if bufwinnr(bufnum) != -1
      cclose
      return
    endif
  endfor
  let winnr = winnr()
  copen
  if winnr() != winnr
    wincmd p
  endif
endfunction


function! QuickFixPrevious()
  try
    cprev
  catch /:E553:/
    clast
  catch /:E42:/
    echo "list empty"
  catch /.*/
    echo v:exception
  endtry
endfunction

function! QuickFixNext()
  try
    cnext
  catch /:E553:/
    cfirst
  catch /:E42:/
    echo "list empty"
  catch /.*/
    echo v:exception
  endtry
endfunction


if !exists('g:cscope_cmd')
  if executable('cscope')
    let g:cscope_cmd = 'cscope'
  else
    call <SID>echo('cscope: command not found')
    finish
  endif
endif

if !exists('g:cscope_interested_files')
  let files = readfile(expand("<sfile>:p:h")."/interested.txt")
  let g:cscope_interested_files = join(map(files, 'v:val."$"'), '\|')
endif

let s:cscope_vim_dir = substitute($HOME,'\\','/','g')."/.cscopex.vim"
let s:index_file = s:cscope_vim_dir.'/index'

function! s:GetBestPath(dir)
  let f = substitute(a:dir,'\\','/','g')
  let bestDir = ""
  for d in keys(s:dbs)
    if stridx(f, d) == 0 && len(d) > len(bestDir)
      let bestDir = d
    endif
  endfor
  return bestDir
endfunction

function! s:ListFiles(dir)
  let d = []
  let f = []
  let cwd = a:dir
  let sl = &l:stl
  while cwd != ''
    let a = split(globpath(cwd, "*"), "\n")
    for fn in a
      if getftype(fn) == 'dir'
        call add(d, fn)
      elseif getftype(fn) != 'file'
        continue
      elseif fn !~? g:cscope_interested_files
        continue
      else
        if stridx(fn, ' ') != -1
          let fn = '"'.fn.'"'
        endif
        call add(f, fn)
      endif
    endfor
    let cwd = len(d) ? remove(d, 0) : ''
    sleep 1m | let &l:stl = 'Found '.len(f).' files, finding in '.cwd | redrawstatus
  endwhile
  sleep 1m | let &l:stl = sl | redrawstatus
  return f
endfunction

function! s:RmDBfiles()
  let odbs = split(globpath(s:cscope_vim_dir, "*"), "\n")
  for f in odbs
    call delete(f)
  endfor
endfunction

function! s:FlushIndex()
  let lines = []
  for d in keys(s:dbs)
    call add(lines, d.'|'.s:dbs[d]['id'].'|'.s:dbs[d]['loadtimes'].'|'.s:dbs[d]['dirty'])
  endfor
  call writefile(lines, s:index_file)
endfunction

function! s:CheckNewFile(dir, newfile)
  let id = s:dbs[a:dir]['id']
  let cscope_files = s:cscope_vim_dir."/".id.".files"
  let files = readfile(cscope_files)
  if len(files) > g:cscope_split_threshold
    let cscope_files = s:cscope_vim_dir."/".id."_inc.files"
    if filereadable(cscope_files)
      let files = readfile(cscope_files)
    else
      let files = []
    endif
  endif
  if count(files, a:newfile) == 0
    call add(files, a:newfile)
    call writefile(files, cscope_files)
  endif
endfunction

function! s:_CreateDB(dir, init)
  let id = s:dbs[a:dir]['id']
  let cscope_files = s:cscope_vim_dir."/".id."_inc.files"
  let cscope_db = s:cscope_vim_dir.'/'.id.'_inc.db'
  if ! filereadable(cscope_files) || a:init
    let cscope_files = s:cscope_vim_dir."/".id.".files"
    let cscope_db = s:cscope_vim_dir.'/'.id.'.db'
    if ! filereadable(cscope_files)
      let files = <SID>ListFiles(a:dir)
      echohl files
      call writefile(files, cscope_files)
    endif
  endif
  exec 'cs kill '.cscope_db
  redir @x
  exec 'silent !'.g:cscope_cmd.' -bkq -i '.cscope_files.' -f'.cscope_db
  redi END
  if @x =~ "\nCommand terminated\n"
    echohl WarningMsg | echo "Failed to create cscope database for ".a:dir.", please check if " | echohl None
  else
    let s:dbs[a:dir]['dirty'] = 0
    exec 'cs add '.cscope_db
  endif
endfunction

function! s:CheckAbsolutePath(dir, defaultPath)
  let d = a:dir
  if d == '.'
    let d = getcwd()
  endif
  while 1
    if !isdirectory(d)
      echohl WarningMsg | echo "Please input a valid path." | echohl None
      let d = input("", a:defaultPath, 'dir')
    elseif (len(d) < 2 || (d[0] != '/' && d[1] != ':'))
      echohl WarningMsg | echo "Please input an absolute path." | echohl None
      let d = input("", a:defaultPath, 'dir')
    else
      break
    endif
  endwhile
  let d = substitute(d,'\\','/','g')
  let d = substitute(d,'/\+$','','')
  return d
endfunction

function! s:InitDB(dir)
  let id = localtime()
  let s:dbs[a:dir] = {}
  let s:dbs[a:dir]['id'] = id
  let s:dbs[a:dir]['loadtimes'] = 0
  let s:dbs[a:dir]['dirty'] = 0
  call <SID>_CreateDB(a:dir, 1)
  call <SID>FlushIndex()
endfunction

function! s:LoadDB(dir)
  cs kill -1
  exe 'cs add '.s:cscope_vim_dir.'/'.s:dbs[a:dir]['id'].'.db'
  if filereadable(s:cscope_vim_dir.'/'.s:dbs[a:dir]['id'].'_inc.db')
    exe 'cs add '.s:cscope_vim_dir.'/'.s:dbs[a:dir]['id'].'_inc.db'
  endif
  let s:dbs[a:dir]['loadtimes'] = s:dbs[a:dir]['loadtimes']+1
  call <SID>FlushIndex()
endfunction

function! s:AutoloadDB(dir)
  let m_dir = <SID>GetBestPath(a:dir)
  if m_dir == ""
    echohl WarningMsg | echo "Can not find proper cscope db, please input a path to generate cscope db for." | echohl None
    let m_dir = input("", a:dir, 'dir')
    if m_dir != ''
      let m_dir = <SID>CheckAbsolutePath(m_dir, a:dir)
      call <SID>InitDB(m_dir)
      call <SID>LoadDB(m_dir)
    endif
  else
    let id = s:dbs[m_dir]['id']
    if cscope_connection(2, s:cscope_vim_dir.'/'.id.'.db') == 0
      call <SID>LoadDB(m_dir)
    endif
  endif
  exec "redraw!"
endfunction

function! s:updateDBs(dirs)
  for d in a:dirs
    call <SID>_CreateDB(d, 0)
  endfor
  call <SID>FlushIndex()
endfunction

function! s:clearDBs(dir)
  cs kill -1
  if a:dir == ""
    let s:dbs = {}
    call <SID>RmDBfiles()
  else
    let id = s:dbs[a:dir]['id']
    call delete(s:cscope_vim_dir."/".id.".files")
    call delete(s:cscope_vim_dir.'/'.id.'.db')
    call delete(s:cscope_vim_dir."/".id."_inc.files")
    call delete(s:cscope_vim_dir.'/'.id.'_inc.db')
    unlet s:dbs[a:dir]
  endif
  call <SID>FlushIndex()
endfunction

function! s:listDBs()
  let dirs = keys(s:dbs)
  if len(dirs) == 0
    echo "You have no cscope dbs now."
  else
    let s = [' ID                   LOADTIMES    PATH']
    for d in dirs
      let id = s:dbs[d]['id']
      if cscope_connection(2, s:cscope_vim_dir.'/'.id.'.db') == 1
        let l = printf("*%d  %10d            %s", id, s:dbs[d]['loadtimes'], d)
      else
        let l = printf(" %d  %10d            %s", id, s:dbs[d]['loadtimes'], d)
      endif
      call add(s, l)
    endfor
    echo join(s, "\n")
  endif
endfunction

function! s:loadIndex()
  let s:dbs = {}
  if ! isdirectory(s:cscope_vim_dir)
    call mkdir(s:cscope_vim_dir)
  elseif filereadable(s:index_file)
    let idx = readfile(s:index_file)
    for i in idx
      let e = split(i, '|')
      if len(e) == 0
        call delete(s:index_file)
        call <SID>RmDBfiles()
      else
        let db_file = s:cscope_vim_dir.'/'.e[1].'.db'
        if filereadable(db_file)
          if isdirectory(e[0])
            let s:dbs[e[0]] = {}
            let s:dbs[e[0]]['id'] = e[1]
            let s:dbs[e[0]]['loadtimes'] = e[2]
            let s:dbs[e[0]]['dirty'] = (len(e) > 3) ? e[3] :0
          else
            call delete(db_file)
          endif
        endif
      endif
    endfor
  else
    call <SID>RmDBfiles()
  endif
endfunction

function! s:preloadDB()
  let dirs = split(g:cscope_preload_path, ';')
  for m_dir in dirs
    let m_dir = <SID>CheckAbsolutePath(m_dir, m_dir)
    if ! has_key(s:dbs, m_dir)
      call <SID>InitDB(m_dir)
    endif
    call <SID>LoadDB(m_dir)
  endfor
endfunction

function! CscopeFind(action, word)
  let dirtyDirs = []
  for d in keys(s:dbs)
    if s:dbs[d]['dirty'] == 1
      call add(dirtyDirs, d)
    endif
  endfor
  if len(dirtyDirs) > 0
    call <SID>updateDBs(dirtyDirs)
  endif
  call <SID>AutoloadDB(getcwd())
  try
    exe ':cs f '.a:action.' '.a:word
    if g:cscope_open_quickfix == 1
      ccl
      cw
    endif
  catch
    echohl WarningMsg | echo 'Can not find '.a:word.' with querytype as '.a:action.'.' | echohl None
  endtry
endfunction

function! CscopeFindInteractive(pat)
  call inputsave()
  let qt = input("\nChoose a querytype for '".a:pat."'(:help cscope-find)\n  c: functions calling this function\n  d: functions called by this function\n  e: this egrep pattern\n  f: this file\n  g: this definition\n  i: files #including this file\n  s: this C symbol\n  t: this text string\n\n  or\n  <querytype><pattern> to query `pattern` instead of '".a:pat."' as `querytype`, Ex. `smain` to query a C symbol named 'main'.\n> ")
  call inputrestore()
  if len(qt) > 1
    call CscopeFind(qt[0], qt[1:])
  elseif len(qt) > 0
    call CscopeFind(qt, a:pat)
  endif
  call feedkeys("\<CR>")
endfunction

function! s:onChange()
  if expand('%:t') =~? g:cscope_interested_files
    let m_dir = <SID>GetBestPath(expand('%:p:h'))
    if m_dir != ""
      let s:dbs[m_dir]['dirty'] = 1
      call <SID>FlushIndex()
      call <SID>CheckNewFile(m_dir, expand('%:p'))
      redraw
      call <SID>echo('Your cscope db will be updated automatically, you can turn off this message by setting g:cscope_silent 1.')
    endif
  endif
endfunction

function! s:CscopeUpdateDB()
  call <SID>clearDBs(getcwd())
  let dirtyDirs = []
  for d in keys(s:dbs)
    if s:dbs[d]['dirty'] == 1
      call add(dirtyDirs, d)
    endif
  endfor
  if len(dirtyDirs) > 0
    call <SID>updateDBs(dirtyDirs)
  endif
  call <SID>preloadDB()
endfunction
" preload here
if g:cscope_auto_update == 1
  au BufWritePost * call <SID>onChange()
endif

set cscopequickfix=s-,g-,d-,c-,t-,e-,f-,i-

function! s:listDirs(A,L,P)
  return keys(s:dbs)
endfunction
" com! -nargs=? -complete=customlist,<SID>listDirs CscopeClear call <SID>clearDBs("<args>")

com! -nargs=0 CscopeList call <SID>listDBs()
com! -nargs=0 CscopeUpdate call <SID>CscopeUpdateDB()
call <SID>loadIndex()
if exists('g:cscope_preload_path')
  if expand('%:t') =~? g:cscope_interested_files
    " if stridx(expand('%:t'), '.c') > -1 || stridx(expand('%:t'), '.h') > -1 || stridx(expand('%:t'), '.cpp') > -1 || stridx(expand('%:t'), '.hpp') > -1 || stridx(expand('%:t'), '.cc') > -1 || stridx(expand('%:t'), '.java') > -1
    call <SID>preloadDB()
  endif
endif


