" TODO: need delete
if exists(':TermdebugGo2')
  finish
endif

command -nargs=* -complete=file -bang TermdebugGo call s:StartDebug(<bang>0, <f-args>)

func s:StartDebug(bang, ...)
  " First argument is the command to debug, second core file or process ID.
  call s:StartDebug_internal({'gdb_args': a:000, 'bang': a:bang})
endfunc

func s:StartDebug_internal(dict)
  let s:vertical = 0
  let s:sourcewin = win_getid(winnr())

  let s:rpcbuf = term_start('NONE', {
	\ 'term_name': 'debugged program',
	\ 'out_cb': function('s:JsonRpcOutput'),
	\ 'vertical': s:vertical,
	\ })
  if s:rpcbuf == 0
    echoerr 'Failed to open the program terminal window'
    return
  endif
  let rpc = job_info(term_getjob(s:rpcbuf))['tty_out']
  let s:rpcwin = win_getid(winnr())

  let dlv_cmd = 'dlv debug --log  --log-dest ' . rpc . ' --log-output rpc  ./main.go'
  " Open a terminal window without a job, to run the debugged program in.
  let s:dlvbuf = term_start(dlv_cmd, {
	\ 'term_name': 'debugged program',
	\ 'vertical': s:vertical,
  \ 'exit_cb': function('s:DlvWinExit'),
  \ 'term_finish': 'close',
	\ })
  if s:dlvbuf == 0
    echoerr 'Failed to open the program terminal window'
    return
  endif
  let dlv = job_info(term_getjob(s:dlvbuf))['tty_out']
  let s:dlvwin = win_getid(winnr())

  let s:breakpoints = {}
  let s:breakpoint_locations = {}

  sign define debugPC linehl=debugPC
  augroup TermDebugGo
    au BufRead * call s:BufRead()
    " au BufUnload * call s:BufUnloaded()
    " au OptionSet background call s:Highlight(0, v:option_old, v:option_new)
  augroup END
endfunc

func s:DlvWinExit(chan, exited)
  echomsg a:exited
  exec 'bwipe! ' . s:rpcbuf
endfunc

func s:JsonRpcOutput(chan, msg)
  let msgs = split(a:msg, "\r")

  for msg in msgs
    if msg[0] == "\n"
      let msg = msg[1:]
    endif

    if msg =~ 'rpc2.CreateBreakpointOut'
      call s:HandleNewBreakpoint(msg, 0)
    elseif msg =~ 'rpc2.ClearBreakpointOut'
      call s:HandleClearBreakpoint(msg)
    elseif msg =~ 'rpc2.CommandOut'
      call s:HandleNext(msg)
    " elseif msg =~ 'rpc2.DetachOut'
    "   exec 'bwipe! ' . s:rpcbuf
    endif
  
  endfor
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
    call sign_define('debugBreakpoint'.nr, {
      \ 'text': substitute(nr, '\..*', '', ''),
      \ 'texthl': hiName,
      \ })
  endif
endfunc

func s:HandleNewBreakpoint(msg, modifiedFlag)
  " debug
  for msg in s:SplitMsg(a:msg)
    if empty(msg)
      return
    endif
    let msg = json_decode(msg)
    let msg = msg['Breakpoint']

    let id = msg['id']
    let fname = msg['file']
    let lnum = msg['line']
    let subid = 0


    call s:CreateBreakpoint(id, 0, v:true)

    if has_key(s:breakpoints, id)
      let entry = s:breakpoints[id]
    else
      let entry = { 
            \ 'fname': fname,
            \ 'line': lnum,
            \ 'subid': 0,
            \ }
      let s:breakpoints[id] = entry
    endif

    let bploc = printf('%s:%d', fname, lnum)
    if !has_key(s:breakpoint_locations, bploc)
      let s:breakpoint_locations[bploc] = []
    endif
    let s:breakpoint_locations[bploc] += [id]

    if bufloaded(fname)
      call s:PlaceSign(id, subid, entry)
    endif
  endfor
endfunc

func s:HandleClearBreakpoint(msg)
  for msg in s:SplitMsg(a:msg)
    if empty(msg)
      return
    endif
    let msg = json_decode(msg)
    let msg = msg['Breakpoint']
    let id = msg['id']

    if has_key(s:breakpoints, id)
      exe 'sign unplace ' . s:Breakpoint2SignNumber(id, 0)
      unlet s:breakpoints[id]
    endif
  endfor
endfunc

func s:HandleNext(msg)
  for msg in s:SplitMsg(a:msg)
    if empty(msg)
      return
    endif

    let wid = win_getid(winnr())

    let msg = json_decode(msg)

    if msg['State']['exited']
      return
    endif

    let msg = msg['State']['currentGoroutine']['userCurrentLoc']

    let fname = msg['file']
    let lnum = msg['line']
    echomsg msg

    call s:GotoSourcewinOrCreateIt()

    if expand('%:p') != fnamemodify(fname, ':p')
      exec 'edit ' . fnameescape(fname)
    endif

    exe lnum
    normal! zv
    exe 'sign unplace ' . s:pc_id
    exe 'sign place ' . s:pc_id . ' line=' . lnum . ' name=debugPC priority=110 file=' . fname

    call win_gotoid(wid)
  endfor
endfunc

func s:GotoSourcewinOrCreateIt()
  if !win_gotoid(s:sourcewin)
    new
    let s:sourcewin = win_getid(winnr())
    " call s:InstallWinbar()
  endif
endfunc

func! s:SplitMsg(s)
  return matchlist(a:s, '{.\{}}')
endfunction

let s:break_id = 14
let s:pc_id = 12

func s:Highlight(init, old, new)
  let default = a:init ? 'default ' : ''
  if a:new ==# 'light' && a:old !=# 'light'
    exe "hi " . default . "debugPC term=reverse ctermbg=lightblue guibg=lightblue"
  elseif a:new ==# 'dark' && a:old !=# 'dark'
    exe "hi " . default . "debugPC term=reverse ctermbg=darkblue guibg=darkblue"
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
  exe 'sign place ' . s:Breakpoint2SignNumber(a:id, a:subid) . ' line=' . a:entry['line'] . ' name=debugBreakpoint' . nr . ' priority=110 file=' . a:entry['fname']
endfunc

func s:BufRead()
  let fname = expand('<afile>:p')
  for [id, entry] in items(s:breakpoints)
    if entry['fname'] == fname
      call s:PlaceSign(id, 0, entry)
    endif
  endfor
endfunc
