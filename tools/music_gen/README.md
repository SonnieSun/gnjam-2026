# music_gen：音乐素材生成脚本

`assets/audio/` 里的所有音频都是这些脚本渲染出来的（Python 3 + numpy + Pillow，不需要别的库）。
所有长度都从 `audio.py` 里的 `BPM = 160` 算出来，改速度只要改这一处再重跑。

## 需要的素材（不在仓库里）

放在一个 `cat_sound/` 文件夹里，结构如下：

```
cat_sound/
  samples/
    99sounds_music_loops/      99Sounds x Monosounds - Music Loops（免费采样包，99sounds.org）
    bigsoundbank_cats/         BigSoundBank 搜 "cat meow" 的 30 个 WAV（CC0，bigsoundbank.com）
    commons_animals/           Wikimedia Commons 的 4 个录音（MeowUSA、Siamese、MIAUEN、海豹，见 assets/audio/README.md 署名）
    my_meows/                  团队自己录的猫叫
  loops/                       渲染输出
  tools/                       就是这个文件夹
```

## 流程

| 脚本 | 做什么 |
| --- | --- |
| `compose_disc.py samples loops` | 第 1 关：骨架、各风格、猫化层、事件层、节奏型、爵士、Entertainer |
| `meow_kit.py` | 把猫叫录音切成按音高命名的短采样（`loops/meow_kit/`） |
| `compose_classics.py loops [曲名...]` | 经典曲；谁唱什么读 `loops/meow_roster.json` |
| `make_sfx.py samples loops deliver/sfx` | 单发音效 |
| `make_deliver.py loops deliver` | 整理成交付文件夹 |
| `package_for_godot.py deliver <项目>` | 拷进 Godot 项目，给 loop 写循环点 |

辅助：`psola.py`（保留音色的变调、"Miiiiao" 拉长）、`slicer.py`（切片 + 测音高）、`miao_score.py`
（给猫叫的"喵感"打分）、`miao_picker.py`（喵选秀页面的试听片段）、`humanmeow.py`（人学猫叫的降噪和
提高共振峰，目前没用）、`check_audio.py`（检查 loop 接缝、削波、频段）、`analyze_ref.py`（分析参考曲）。

`meow_roster.json` 是在喵选秀页面上保存的猫叫分工：long（长音组）、accent（E5 以下长音、句尾喊）、
short（短音、喵鼓、猫和声），数字是候选编号（`compose_classics.py` 里的 `CANDIDATES`）。
