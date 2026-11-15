extends SceneTree
var records: Array = []
const OUT := "res://docs/text_audit"
func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	call_deferred("_run")
func _load(path: String) -> void:
	change_scene_to_file(path)
	await create_timer(0.65).timeout
func _texts(node: Node, items: Array) -> void:
	if node is Label or node is Label3D or node is BaseButton or node is RichTextLabel or node is LineEdit:
		var value := str(node.get("text"))
		if not value.is_empty(): items.append({"node":str(node.get_path()),"text":value})
	if node is OptionButton:
		for i in node.item_count: items.append({"node":str(node.get_path()),"text":node.get_item_text(i)})
	for child in node.get_children(): _texts(child, items)
func _shot(id: String, category: String, title: String, fixture := false) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OUT.path_join(id + ".png"))
	var items: Array = []
	_texts(current_scene, items)
	records.append({"id":id,"category":category,"title":title,"fixture":fixture,"texts":items})
	var f := FileAccess.open(OUT.path_join("screens.json"),FileAccess.WRITE)
	f.store_string(JSON.stringify(records,"\t"))
	print("CAPTURE ",id)
func _run() -> void:
	await _load(Levels.MENU_SCENE)
	for i in 5:
		await _shot("menu%d" % i,"A","关卡菜单 / " + Levels.title())
		current_scene.turn(1)
		await create_timer(0.4).timeout
	for i in 5:
		Levels.selected=i
		await _load(Levels.GAME_SCENE)
		current_scene.judge.set_process(false)
		await _shot("game%d" % i,"B","游玩画面 / " + Levels.title())
		if i==0:
			var hud=current_scene.hud
			hud.set_stats(12800,23)
			for spec in [[NoteData.Result.PERFECT,0.0,"perfect"],[NoteData.Result.GREAT,-0.06,"great_early"],[NoteData.Result.GREAT,0.06,"great_late"],[NoteData.Result.GOOD,-0.11,"good_early"],[NoteData.Result.GOOD,0.13,"good_late"],[NoteData.Result.MISS,0.14,"miss"]]:
				hud.show_judgement(spec[0],spec[1])
				await _shot(spec[2],"C","判定 / " + hud.judge_label.text,true)
			hud.show_combo_milestone(50)
			await _shot("combo","D","分数、连击与里程碑",true)
			hud.show_note("LOOK: Y2K_JPEG")
			await _shot("look","H","调试风格提示",true)
			hud.reset()
			hud.judge_label.text=""
			current_scene.judge.score=12800
			current_scene.judge.max_combo=50
			current_scene.judge.counts={NoteData.Result.PERFECT:100,NoteData.Result.GREAT:25,NoteData.Result.GOOD:16,NoteData.Result.MISS:3}
			current_scene.judge.hit_offsets.clear()
			current_scene.judge.hit_offsets.append(0.012)
			current_scene._clear_level()
			await _shot("result","F","通关结算",true)
			hud.result_label.visible=false
			current_scene.toggle_editor()
			var tabs:TabContainer=current_scene._editor._panel.find_children("*","TabContainer",true,false)[0]
			for t in tabs.get_tab_count():
				tabs.current_tab=t
				await _shot("edit%d"%t,"I","游戏内编辑 / "+tabs.get_tab_title(t))
		if i==2:
			for stage in 3:
				current_scene.start_from(stage)
				current_scene.judge.set_process(false)
				await create_timer(0.3).timeout
				await _shot("orbit%d"%stage,"E","蓄力关卡 / "+current_scene.chart.sections[stage].title)
			var section=current_scene._current
			section.set_process(false)
			for status in ["LISTEN / GET READY","CHARGE  4 / 8","READY  8 / 8","HIT THE EARTH!","MISSED THE BEAT","LOW CHARGE","POWER SHOT!"]:
				section._status_label.text=status
				section._hint_label.text="Fast taps to the hats" if status.begins_with("CHARGE") else "Strike once when the ring meets"
				await _shot("charge%d"%records.size(),"E","蓄力状态 / "+status,true)
		if i==4:
			var section=current_scene._current
			section.set_process(false)
			var n=NoteData.new()
			n.beat=section.song_beat()
			section._hold_lens.clear()
			section._hold_lens[0]=4.0
			section._pattern_len=4.0
			section._pattern_origin=n.beat
			section.notes.clear()
			section.notes.append(n)
			section._holding=n
			section.queue_redraw()
			await _shot("hold","E","长按倒计时",true)
			section._holding=null
			section._failed[n]=true
			section.queue_redraw()
			await _shot("hold_failed","E","长按失败",true)
	await _load("res://scenes/calibrate.tscn")
	await _shot("calibrate1","G","校准第一步 / 按键延迟")
	current_scene._start_visual()
	await _shot("calibrate2","G","校准第二步 / 视觉偏移",true)
	await _load("res://scenes/tools/jukebox.tscn")
	await _shot("jukebox","J","曲库 / Jukebox")
	await _load("res://scenes/tools/meow_studio.tscn")
	for kind in ["drums","melody"]:
		current_scene._tab.new_pattern(kind)
		await _shot("studio_"+kind,"J","喵谱工作室 / "+kind,true)
	await _load("res://levelkit/level_editor.tscn")
	await _shot("level_editor","K","独立关卡编辑器")
	current_scene.start_playtest()
	await _shot("playtest","K","独立四轨试玩")
	current_scene.playtest._say("RESULT  95%",Color.WHITE)
	await _shot("playtest_result","K","独立试玩结算",true)
	print("AUDIT_CAPTURE_COMPLETE ",records.size())
	quit()
