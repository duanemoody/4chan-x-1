ThreadUpdater =
  init: ->
    return if g.VIEW isnt 'thread' or !Conf['Thread Updater']

    checked = if Conf['Auto Update'] then 'checked' else ''
    @dialog = sc = $.el 'span',
      innerHTML: "<span id=update-status></span><span id=update-timer title='Update now'></span>"
      id:        'updater'

    @timer  = $ '#update-timer',  sc
    @status = $ '#update-status', sc

    $.on @timer,  'click', ThreadUpdater.update
    $.on @status, 'click', ThreadUpdater.update

    @checkPostCount = 0

    Header.addShortcut sc

    subEntries = []
    for name, conf of Config.updater.checkbox
      checked = if Conf[name] then 'checked' else ''
      el = $.el 'label',
        title:    "#{conf[1]}"
        innerHTML: "<input name='#{name}' type=checkbox #{checked}> #{name}"
      input = el.firstElementChild
      $.on input, 'change', $.cb.checked
      if input.name is 'Scroll BG'
        $.on input, 'change', ThreadUpdater.cb.scrollBG
        ThreadUpdater.cb.scrollBG()
      subEntries.push el: el

    settings = $.el 'span',
      innerHTML: '<a href=javascript:;>Interval</a>'

    $.on settings, 'click', @intervalShortcut

    subEntries.push el: settings

    $.event 'AddMenuEntry',
      type: 'header'
      el: $.el 'span',
        textContent: 'Updater'
      order: 110
      subEntries: subEntries

    Thread::callbacks.push
      name: 'Thread Updater'
      cb:   @node

  node: ->
    ThreadUpdater.thread       = @
    ThreadUpdater.root         = @OP.nodes.root.parentNode
    ThreadUpdater.lastPost     = +ThreadUpdater.root.lastElementChild.id.match(/\d+/)[0]
    ThreadUpdater.outdateCount = 0
    ThreadUpdater.lastModified = '0'

    ThreadUpdater.cb.interval.call $.el 'input', value: Conf['Interval']

    $.on window, 'online offline',   ThreadUpdater.cb.online
    $.on d,      'QRPostSuccessful', ThreadUpdater.cb.post
    $.on d,      'visibilitychange', ThreadUpdater.cb.visibility

    ThreadUpdater.cb.online()

  ###
  http://freesound.org/people/pierrecartoons1979/sounds/90112/
  cc-by-nc-3.0
  ###
  beep: 'data:audio/wav;base64,<%= grunt.file.read("src/audio/beep.wav", {encoding: "base64"}) %>'

  cb:
    online: ->
      if ThreadUpdater.online = navigator.onLine
        ThreadUpdater.outdateCount = 0
        ThreadUpdater.set 'timer', ThreadUpdater.getInterval()
        ThreadUpdater.update()
        ThreadUpdater.set 'status', null, null
      else
        ThreadUpdater.set 'timer', null
        ThreadUpdater.set 'status', 'Offline', 'warning'
      ThreadUpdater.cb.autoUpdate()
    post: (e) ->
      return unless e.detail.threadID is ThreadUpdater.thread.ID
      ThreadUpdater.outdateCount = 0
      setTimeout ThreadUpdater.update, 1000 if ThreadUpdater.seconds > 2
    checkpost: ->
      unless g.DEAD or ThreadUpdater.foundPost or ThreadUpdater.checkPostCount >= 10
        return setTimeout ThreadUpdater.update, ++ThreadUpdater.checkPostCount * 500
      ThreadUpdater.checkPostCount = 0
      delete ThreadUpdater.foundPost
      delete ThreadUpdater.postID
    visibility: ->
      return if d.hidden
      # Reset the counter when we focus this tab.
      ThreadUpdater.outdateCount = 0
      if ThreadUpdater.seconds > ThreadUpdater.interval
        ThreadUpdater.set 'timer', ThreadUpdater.getInterval()
    scrollBG: ->
      ThreadUpdater.scrollBG = if Conf['Scroll BG']
        -> true
      else
        -> not d.hidden
    autoUpdate: ->
      if ThreadUpdater.online
        ThreadUpdater.timeoutID = setTimeout ThreadUpdater.timeout, 1000
      else
        clearTimeout ThreadUpdater.timeoutID
    interval: ->
      val = parseInt @value, 10
      ThreadUpdater.interval = @value = val
      $.cb.value.call @
    load: ->
      {req} = ThreadUpdater
      switch req.status
        when 200
          g.DEAD = false
          ThreadUpdater.parse JSON.parse(req.response).posts
          ThreadUpdater.lastModified = req.getResponseHeader 'Last-Modified'
          ThreadUpdater.set 'timer', ThreadUpdater.getInterval()
        when 404
          g.DEAD = true
          ThreadUpdater.set 'timer', null
          ThreadUpdater.set 'status', '404', 'warning'
          clearTimeout ThreadUpdater.timeoutID
          ThreadUpdater.thread.kill()
          $.event 'ThreadUpdate',
            404: true
            thread: ThreadUpdater.thread
        else
          ThreadUpdater.outdateCount++
          ThreadUpdater.set 'timer',  ThreadUpdater.getInterval()
          ###
          Status Code 304: Not modified
          By sending the `If-Modified-Since` header we get a proper status code, and no response.
          This saves bandwidth for both the user and the servers and avoid unnecessary computation.
          ###
          # XXX 304 -> 0 in Opera
          [text, klass] = if [0, 304].contains req.status
            [null, null]
          else
            ["#{req.statusText} (#{req.status})", 'warning']
          ThreadUpdater.set 'status', text, klass

      if ThreadUpdater.postID
        ThreadUpdater.cb.checkpost @status

      delete ThreadUpdater.req

  getInterval: ->
    i = ThreadUpdater.interval
    j = Math.min ThreadUpdater.outdateCount, 10
    unless d.hidden
      # Lower the max refresh rate limit on visible tabs.
      j = Math.min j, 7
    ThreadUpdater.seconds =
      if Conf['Optional Increase']
        Math.max i, [0, 5, 10, 15, 20, 30, 60, 90, 120, 240, 300][j]
      else
        i

  intervalShortcut: ->
    Settings.open 'Advanced'
    settings = $.id 'fourchanx-settings'
    $('input[name=Interval]', settings).focus()

  set: (name, text, klass) ->
    el = ThreadUpdater[name]
    if node = el.firstChild
      # Prevent the creation of a new DOM Node
      # by setting the text node's data.
      node.data = text
    else
      el.textContent = text
    el.className = klass if klass isnt undefined

  timeout: ->
    ThreadUpdater.timeoutID = setTimeout ThreadUpdater.timeout, 1000
    unless n = --ThreadUpdater.seconds
      ThreadUpdater.update()
    else if n <= -60
      ThreadUpdater.set 'status', 'Retrying', null
      ThreadUpdater.update()
    else if n > 0
      ThreadUpdater.set 'timer', n

  update: ->
    return unless ThreadUpdater.online
    ThreadUpdater.seconds = 0
    ThreadUpdater.set 'timer', '...'
    if ThreadUpdater.req
      # abort() triggers onloadend, we don't want that.
      ThreadUpdater.req.onloadend = null
      ThreadUpdater.req.abort()
    url = "//api.4chan.org/#{ThreadUpdater.thread.board}/res/#{ThreadUpdater.thread}.json"
    ThreadUpdater.req = $.ajax url, onloadend: ThreadUpdater.cb.load,
      headers: 'If-Modified-Since': ThreadUpdater.lastModified

  updateThreadStatus: (title, OP) ->
    titleLC = title.toLowerCase()
    return if ThreadUpdater.thread["is#{title}"] is !!OP[titleLC]
    unless ThreadUpdater.thread["is#{title}"] = !!OP[titleLC]
      message = if title is 'Sticky'
        'The thread is not a sticky anymore.'
      else
        'The thread is not closed anymore.'
      new Notification 'info', message, 30
      $.rm $ ".#{titleLC}Icon", ThreadUpdater.thread.OP.nodes.info
      return
    message = if title is 'Sticky'
      'The thread is now a sticky.'
    else
      'The thread is now closed.'
    new Notification 'info', message, 30
    icon = $.el 'img',
      src: "//static.4chan.org/image/#{titleLC}.gif"
      alt: title
      title: title
      className: "#{titleLC}Icon"
    root = $ '[title="Quote this post"]', ThreadUpdater.thread.OP.nodes.info
    if title is 'Closed'
      root = $('.stickyIcon', ThreadUpdater.thread.OP.nodes.info) or root
    $.after root, [$.tn(' '), icon]

  parse: (postObjects) ->
    OP = postObjects[0]
    Build.spoilerRange[ThreadUpdater.thread.board] = OP.custom_spoiler

    ThreadUpdater.updateThreadStatus 'Sticky', OP
    ThreadUpdater.updateThreadStatus 'Closed', OP
    ThreadUpdater.thread.postLimit = !!OP.bumplimit
    ThreadUpdater.thread.fileLimit = !!OP.imagelimit

    posts = [] # post objects
    index = [] # existing posts
    files = [] # existing files
    count = 0  # new posts count
    # Build the index, create posts.
    for postObject in postObjects
      num = postObject.no
      index.push num
      files.push num if postObject.fsize
      continue if num <= ThreadUpdater.lastPost
      # Insert new posts, not older ones.
      count++
      node = Build.postFromObject postObject, ThreadUpdater.thread.board
      posts.push new Post node, ThreadUpdater.thread, ThreadUpdater.thread.board

    deletedPosts = []
    deletedFiles = []
    # Check for deleted posts/files.
    for ID, post of ThreadUpdater.thread.posts
      # XXX tmp fix for 4chan's racing condition
      # giving us false-positive dead posts.
      # continue if post.isDead
      ID = +ID
      if post.isDead and index.contains ID
        post.resurrect()
      else unless index.contains ID
        post.kill()
        deletedPosts.push post
      else if post.file and !post.file.isDead and not files.contains ID
        post.kill true
        deletedFiles.push post
      if ThreadUpdater.postID
        if ID is ThreadUpdater.postID
          ThreadUpdater.foundPost = true

    unless count
      ThreadUpdater.set 'status', null, null
      ThreadUpdater.outdateCount++

    else
      ThreadUpdater.set 'status', "+#{count}", 'new'
      ThreadUpdater.outdateCount = 0
      if Conf['Beep'] and d.hidden and Unread.posts and !Unread.posts.length
        unless ThreadUpdater.audio
          ThreadUpdater.audio = $.el 'audio', src: ThreadUpdater.beep
        ThreadUpdater.audio.play()

      ThreadUpdater.lastPost = posts[count - 1].ID
      Main.callbackNodes Post, posts

      scroll = Conf['Auto Scroll'] and ThreadUpdater.scrollBG() and
        ThreadUpdater.root.getBoundingClientRect().bottom - doc.clientHeight < 25

      for key, post of posts
        continue unless posts.hasOwnProperty key
        if post.cb
          unless post.cb.call post
            $.add ThreadUpdater.root, post.nodes.root
        else
          $.add ThreadUpdater.root, post.nodes.root

      if scroll
        if Conf['Bottom Scroll']
          <% if (type === 'crx') { %>d.body<% } else { %>doc<% } %>.scrollTop = d.body.clientHeight
        else
          Header.scrollToPost nodes[0]

      $.queueTask ->
        # Enable 4chan features.
        threadID = ThreadUpdater.thread.ID
        {length} = $$ '.thread > .postContainer', ThreadUpdater.root
        Fourchan.parseThread threadID, length - count, length

    $.event 'ThreadUpdate',
      404: false
      thread: ThreadUpdater.thread
      newPosts: posts
      deletedPosts: deletedPosts
      deletedFiles: deletedFiles
      postCount: OP.replies + 1
      fileCount: OP.images + (!!ThreadUpdater.thread.OP.file and !ThreadUpdater.thread.OP.file.isDead)