" TODO: need delete
if exists(':TermdebugGo2')
  finish
endif

command -nargs=* -complete=file -bang TermdebugGo call s:StartDebug(<bang>0, <f-args>)

if !exists('g:termdebugger_go')
  let g:termdebugger_go = 'dlv'
endif

let s:break_id = 14
let s:pc_id = 12

function s:GetCommand() 
  return [g:termdebugger_go]
endfunction

func s:StartDebug(bang, ...)
  " First argument is the command to debug, second core file or process ID.
  call s:StartDebug_internal({'dlv_args': ['debug'] + a:000, 'bang': a:bang})
endfunc

func s:StartDebug_internal(dict)
  if exists('s:dlvwin')
    echoerr 'Terminal debugger already running, cannot run two'
    return
  endif

  let dlvcmd = s:GetCommand()
  if !executable(dlvcmd[0])
    echoerr 'Cannot execute debugger program "' . dlvcmd[0] . '"'
    return
  endif

  let s:rpcwin = 0

  " if exists('#User#TermdebugGoStartPre')
  "   doauto <nomodeline> User TermdebugStartPre
  " endif

  let s:sourcewin = win_getid(winnr())

  " Remember the old value of 'signcolumn' for each buffer that it's set in, so
  " that we can restore the value for all buffers.
  let b:save_signcolumn = &signcolumn
  let s:signcolumn_buflist = [bufnr('%')]

  " let s:save_columns = 0
  let s:vertical = 0

  call s:StartDebug_term(a:dict)
endfunc

func s:CheckRunning()
  let dlvproc = term_getjob(s:dlvbuf)
  if dlvproc == v:null || job_status(dlvproc) !=# 'run'
    echoerr string(s:GetCommand()[0]) . ' exited unexpectedly'
    call s:CloseBuffers()
    return ''
  endif
  return 'ok'
endfunc

func s:StartDebug_term(dict)
  let s:logbuf = term_start('NONE', {
	\ 'term_name': 'json rpc log',
	\ 'vertical': s:vertical,
	\ })
  if s:logbuf == 0
    echoerr 'Failed to open the program terminal window'
    exec 'bwipe! ' . s:logbuf
    return
  endif

  let logpty = job_info(term_getjob(s:logbuf))['tty_out']
  let s:rpcwin = win_getid(winnr())

  let dlv_args = get(a:dict, 'dlv_args', [])
  " let proc_args = get(a:dict, 'proc_args', [])

  " dlv debug --log  --log-dest /dev/pts/13 --log-output logpty  ./main.go
  let dlv_cmd = s:GetCommand()
  let dlv_cmd += dlv_args[0:1]
   " let dlv_cmd += ['--log', '--log-output', 'rpc']
  " let dlv_cmd += ['--log-dest', logpty]
  let dlv_cmd += ['--tty', logpty]
  
  let dlv_cmd += len(dlv_args[1:]) == 0 ?  ['./main.go'] : dlv_args[1:]

  " echom join(dlv_cmd, " ")

  " Open a terminal window without a job, to run the debugged program in.
  let s:dlvbuf = term_start(join(dlv_cmd, ' '), {
	\ 'term_name': 'delve debugger',
  \ 'out_cb': function('s:DlvMsgOutput'),
  \ 'term_finish': 'close',
	\ })
  if s:dlvbuf == 0
    echoerr 'Failed to open the program terminal window'
    call s:EndTermDebug()
    return
  endif
  let s:dlvwin = win_getid(winnr())

  let try_count = 0
  while 1
    if s:CheckRunning() != 'ok'
      return
    endif

    for lnum in range(1, 200)
      if term_getline(s:dlvbuf, lnum) =~ '(dlv)'
        let try_count = 9999
        break
      endif
    endfor

    let try_count += 1
    if try_count > 300
      " done or give up after five seconds
      break
    endif
    sleep 10m
  endwhile

  call job_setoptions(term_getjob(s:dlvbuf), {'exit_cb': function('s:EndTermDebug')})

  let s:breakpoints = {}
  let s:breakpoint_locations = {}

  sign define debugPC linehl=debugPC
  augroup TermDebugGo
    au BufRead * call s:BufRead()
    au BufUnload * call s:BufUnloaded()
    " au OptionSet background call s:Highlight(0, v:option_old, v:option_new)
  augroup END
endfunc

func s:EndTermDebug(chan, exited)
  call s:CloseBuffers()
  unlet! s:dlvwin

  " Restore 'signcolumn' in all buffers for which it was set.
  call win_gotoid(s:sourcewin)
  let was_buf = bufnr('%')
  for bufnr in s:signcolumn_buflist
    if bufexists(bufnr)
      exec bufnr . "buf"
      if exists('b:save_signcolumn')
        let &signcolumn = b:save_signcolumn
        unlet b:save_signcolumn
      endif
    endif
  endfor
  exec was_buf . "buf"

  exec 'sign unplace ' . s:pc_id
  for [id, entry] in items(s:breakpoints)
    exec 'sign unplace ' . s:Breakpoint2SignNumber(id, 0)
  endfor
  unlet! s:breakpoints
  unlet! s:breakpoint_locations

  au! TermDebugGo
endfunc

func s:CloseBuffers()
  exec 'bwipe! ' . s:logbuf
endfunc

let s:BreakpointSigns = []

func s:CreateBreakpoint(id, subid, enabled)
  let nr = printf('%d.%d', a:id, a:subid)
  if index(s:BreakpointSigns, nr) == -1
    call add(s:BreakpointSigns, nr)
    if a:enabled == "n"
      let hiName = "debugBreakpointDisabled"
    else
      let hiName = "debugBreakpoint"
    endif
    exec "sign define debugBreakpoint" . nr 
          \ . " text="
          \ . substitute(nr, '\..*', '', '')
          \ . " texthl=" . hiName

  endif
endfunc

func s:OnBreakpointAdded(id, fname, lnum)
  call s:CreateBreakpoint(a:id, 0, v:true)

  if has_key(s:breakpoints, a:id)
    let entry = s:breakpoints[a:id]
  else
    let entry = { 
          \ 'fname': a:fname,
          \ 'line': a:lnum,
          \ 'subid': 0,
          \ }
    let s:breakpoints[a:id] = entry
  endif

  let bploc = printf('%s:%d', a:fname, a:lnum)
  if !has_key(s:breakpoint_locations, bploc)
    let s:breakpoint_locations[bploc] = []
  endif
  let s:breakpoint_locations[bploc] += [a:id]

  if bufloaded(a:fname)
    call s:PlaceSign(a:id, 0, entry)
  endif
endfunc

func s:OnBreakpointCleared(id)
  let id = a:id

  if has_key(s:breakpoints, id)
    exec 'sign unplace ' . s:Breakpoint2SignNumber(id, 0)
    let entry = s:breakpoints[id]
    unlet entry['placed']
    unlet s:breakpoints[id]
  endif
endfunc

func s:DlvMsgOutput(chan,msg)
  if a:msg =~ 'not on topmost frame'
    call term_sendkeys(s:dlvbuf, "frame 0")
    return
  elseif a:msg =~ '\vFrame \d+: (.{-}).go:(\d+)'
    let frame = matchlist(a:msg, '\vFrame \d+: (.{-}):(\d+)')
    call s:UpdateCursorPos(frame[1], frame[2])
    return
  elseif a:msg =~ '\v\>.{-}\(\) (.{-})\.go:(\d+)'
    let frame = matchlist(a:msg, '\v\>.{-}\(\) (.{-}):(\d+)')
    call s:UpdateCursorPos(frame[1], frame[2])
    return
  elseif a:msg =~ '\vBreakpoint (\d+) set at.{-}for.{-}\(\) (.{-}):(\d+)'
    let item = matchlist(a:msg, '\vBreakpoint (\d+) set at.{-}for.{-}\(\) (.{-}):(\d+)')
    call s:OnBreakpointAdded(str2nr(item[1]), item[2], item[3])
  elseif a:msg =~ '\vBreakpoint (\d+) cleared at'
    let id = matchlist(a:msg, '\vBreakpoint (\d+) cleared at')[1]
    call s:OnBreakpointCleared(str2nr(id))
  elseif a:msg =~ 'has exited with status'
    exec 'sign unplace ' . s:pc_id
    return
  endif
endfunc

func s:UpdateCursorPos(fname, line)
  let wid = win_getid(winnr())
  let fname = a:fname
  let lnum = a:line

  call s:GotoSourcewinOrCreateIt()

  if expand('%:p') != fnamemodify(fname, ':p')
    exec 'edit ' . fnameescape(fname)
  endif

  exec lnum
  normal! zv
  exec 'sign unplace ' . s:pc_id
  exec 'sign place ' . s:pc_id . ' line=' . lnum . ' name=debugPC priority=110 file=' . fname
  call win_gotoid(wid)
endfunc

func s:GotoSourcewinOrCreateIt()
  if !win_gotoid(s:sourcewin)
    new
    let s:sourcewin = win_getid(winnr())
    " call s:InstallWinbar()
  endif
endfunc

func! s:DecodeMsg(msg)
  let msg = matchstr(a:msg, '{.*}')
  if empty(msg)
    return
  endif

  let retMsg = {}
  try
    let retMsg = json_decode(msg)
  catch
   echoerr "Decode msg error:" . msg
  endtry
  return retMsg
endfunction


func s:Highlight(init, old, new)
  let default = a:init ? 'default ' : ''
  if a:new ==# 'light' && a:old !=# 'light'
    exec "hi " . default . "debugPC term=reverse ctermbg=lightblue guibg=lightblue"
  elseif a:new ==# 'dark' && a:old !=# 'dark'
    exec "hi " . default . "debugPC term=reverse ctermbg=darkblue guibg=darkblue"
  endif
endfunc

call s:Highlight(1, '', &background)
hi default debugBreakpoint term=reverse ctermbg=red guibg=red
hi default debugBreakpointDisabled term=reverse ctermbg=gray guibg=gray

func s:Breakpoint2SignNumber(id, subid)
  return s:break_id + a:id * 1000 + a:subid
endfunction


func s:PlaceSign(id, subid, entry)
  let nr = printf("%d.%d", a:id, a:subid)
  let sn = s:Breakpoint2SignNumber(a:id, a:subid)
  exec 'sign place ' . sn
        \ . ' line=' . a:entry['line']
        \ . ' name=debugBreakpoint' . nr
        \ . ' priority=110'
        \ . ' file=' . a:entry['fname']
  let a:entry['placed'] = 1
endfunc

func s:BufRead()
  let fname = expand('<afile>:p')
  for [id, entry] in items(s:breakpoints)
    
    if fnamemodify(entry['fname'], ':p') == fname
      call s:PlaceSign(id, 0, entry)
    endif
  endfor
endfunc


" Handle a BufUnloaded autocommand event: unplace any signs.
func s:BufUnloaded()
  let fname = expand('<afile>:p')
  for [id, entry] in items(s:breakpoints)
    if entry['fname'] == fname
      let entry['placed'] = 0
    endif
  endfor
endfunc
