# 09 · 设备实体参考（米家 / 海尔）

> 用 HA 时最容易踩的不是命令，而是**实体 ID 猜错**。这一页给结构，不给具体值 ——
> 你机器上的 4 位哈希不同，请用 `ha_list_entities` 拉自己的列表。

## 9.1 怎么拿自己的实体列表

```bash
# 方式一：走 Hermes 工具
hermes tools list                      # 确认 homeassistant 工具集在
# 然后在对话里说「列出我家所有设备」，或直接调：
#   ha_list_entities(domain="light")
#   ha_list_entities(domain="climate")

# 方式二：直连 HA REST
curl -s -H "Authorization: Bearer <HA_TOKEN>" \
  http://<HOME_TS_IP>:8123/api/states \
  | python3 -c "import sys,json;[print(s['entity_id']) for s in json.load(sys.stdin)]"
```

## 9.2 实体 ID 的构成规律

米家 / 海尔接入后，实体 ID 一般是：

```
<domain>.<品牌或型号>_<4位设备哈希>_<功能>
```

- `domain`：`light` / `switch` / `climate` / `sensor` / `media_player` …
- `4位设备哈希`：**每台设备不同**，由设备标识推导，无法猜
- 同一个物理设备的**指示灯**和**主开关**是两个不同实体

常见形态举例：

| 中文名 | domain | entity_id 结构 |
|---|---|---|
| Philips 米家台灯 | light | `light.philips_sread1_<hash>_light` |
| 米家显示器挂灯 2 | light | `light.xiaomi_bar2_<hash>_light` |
| 米家空调（插座型）| climate | `climate.lumi_mcn02_<hash>_air_conditioner` |
| 海尔挂式空调 | climate | `climate.gua_shi_kong_diao_climate` |
| 小爱音箱（L15A 类）| media_player | `media_player.xiaomi_l15a_<hash>_play_control` |
| 电脑插座（主开关）| switch | `switch.cuco_v3_<hash>_switch` |
| 热水器插座（主开关）| switch | `switch.cuco_cp1d_<hash>_switch` |
| 温湿度计-温度 | sensor | `sensor.miaomiaoce_t2_<hash>_temperature` |
| 温湿度计-湿度 | sensor | `sensor.miaomiaoce_t2_<hash>_relative_humidity` |
| 温湿度计-电量 | sensor | `sensor.miaomiaoce_t2_<hash>_battery_level` |
| 海尔冰箱-冷藏/冷冻 | sensor | `sensor.bing_xiang_<型号>_leng_cang_...` / `..._leng_dong_...` |

> `gua_shi_kong_diao`（拼音"挂式空调"）、`bing_xiang`（拼音"冰箱"）这类**中文拼音域名**来自集成作者的中文命名映射，不含设备哈希。

## 9.3 三个必须记住的陷阱

### ① 温度传感器的原始单位可能是华氏度

部分米家温湿度计上报 `°F`。用户问「多少度」时直接播报会错得离谱。

```
°C = (°F − 32) × 5/9        例：81.5 °F → 27.5 °C
```

**省事做法**：该实体的属性里通常自带摄氏值（形如 `temperature-2-1: 27.5`），可直接取。

**让 AI 记住**：在角色提示词里明确写「温湿度计温度是华氏度，回答前换算成摄氏度」。

### ② 冰箱没有总电源开关

`switch.bing_xiang_*_su_dong`（速冻）`_su_leng`（速冷）`_zhi_neng`（智能）`_jia_ri`（假日）`_ren_gong_zhi_neng`（人工智）等**都是子功能**，不是总开关。

**看冰箱状态请走 temperature 传感器**，别指望开关。

### ③ 插座设备的子开关 ≠ 主开关

以某插座为例：

- ✅ **主开关**：`switch.cuco_v3_<hash>_switch`
- ❌ 子功能 / 状态位：`_on_2`、`_on_3`、`_on_4`、`_physical_control_locked`（童锁）、`_switch_status`
- 另外可能还有一个 `light.cuco_v3_<hash>_indicator_light`（**指示灯**，不是通电开关）

**症状**：你说"打开电脑插座"，AI 开了 `_on_2`，设备其实没通电。

**同理**：海尔挂式空调有约 **30 个子功能开关**（自清洁 / 新风 / PM2.5 / 除菌 / 语音 / 电子锁…）。
**控制空调请用 `climate.gua_shi_kong_diao_climate`（climate 域）**，不要用那一堆 switch。

## 9.4 建议：把常用实体写进角色提示词

169 个实体不要全塞给模型（会把 prompt 撑爆，见 [06 篇](06-performance.md)）。
建议在 Hermes 的角色提示词 / 记忆里，只写清**常用的十来个**「中文名 → entity_id」映射，
并明确"**需要时只查目标设备，不要列全部**"。

示例片段：

```text
家里的常用设备（entity_id 已核对）：
- 台灯：light.philips_sread1_<hash>_light
- 电脑插座（主开关）：switch.cuco_v3_<hash>_switch
- 海尔挂式空调：climate.gua_shi_kong_diao_climate
- 温湿度计：sensor.miaomiaoce_t2_<hash>_temperature（华氏度，回答前换算）

规则：
1. 温湿度计温度是华氏度，先换算成摄氏度再回答
2. 冰箱只看温度传感器，没有总开关
3. 插座请用 _switch 主开关，不要用 _on_2 / _indicator_light
4. 只查目标设备，不要调用 ha_list_entities 列全部设备
5. 中文口语化，两句话以内
```
