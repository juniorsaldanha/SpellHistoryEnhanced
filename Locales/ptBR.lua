-- ptBR.lua - Brazilian Portuguese locale for Spell Combo History.
-- Overrides the English defaults from enUS.lua. Any key omitted here falls
-- back to the English text. Encoded as UTF-8.
if GetLocale() ~= "ptBR" then return end
local _, ns = ...
local L = ns.L

-- Movable anchor hint shown while the bar is unlocked.
L["MOVE_HINT"] = "MOVER\nClique direito para travar"

-- Options panel.
L["OPTIONS_TITLE"] = "Configurações do Spell Combo History"
L["RESTART_TIMEOUT"] = "Tempo para reiniciar"
L["LOCK_POSITION"] = "Travar posição"
L["USE_GRID_SNAP"] = "Usar grade e encaixe"
L["MAX_ICONS"] = "Máximo de ícones"
L["BG_TRANSPARENCY"] = "Transparência do fundo"
L["UI_SCALE"] = "Escala da interface"
L["SPELL_QUEUE_WINDOW"] = "Janela de fila de magias"
L["QUEUE_HELP"] = "Valores mais altos permitem que magias pré-inseridas sejam ativadas suavemente, mas dificultam a troca rápida de habilidades.\nValores mais baixos são afetados diretamente pelo ping, podendo desperdiçar tempo entre as magias."
L["CHECK_CURRENT"] = "Verificar valor atual"
L["CLEAR_HISTORY"] = "Limpar histórico"
L["RESET_POSITION"] = "Redefinir posição"

-- Chat messages (printed after the "[SpellCombo]" prefix).
L["MSG_POSITION_LOCKED"] = "Posição travada com o clique direito."
L["MSG_CURRENT_QUEUE"] = "SpellQueueWindow atual:"
L["MSG_HISTORY_CLEARED"] = "O histórico foi limpo."
L["MSG_POSITION_RESET"] = "A posição foi redefinida para o centro."

-- Display words rendered on/near the icons.
L["START"] = "INÍCIO"
L["RESTART"] = "REINÍCIO"
L["PERFECT"] = "PERFEITO"

-- Combo tier labels, shown as the streak grows.
L["COMBO_STREAK"] = "SEQUÊNCIA"
L["COMBO_RAMPAGE"] = "FÚRIA"
L["COMBO_INSANE"] = "INSANO"
L["COMBO_GODLIKE"] = "DIVINO"
L["COMBO_LEGEND"] = "LENDÁRIO"
