--[[
MajorTom: save words and phrases while reading.

Adds one button to the text-selection menu and one to the dictionary popup.
Both translate what you picked, show it, and save it only if you say so.

Saved lines go to a JSONL file on the device. Nothing is sent anywhere; the
Mac pulls the file over USB and imports it into the MajorTom library.

Translation is KOReader's own translator (no API key, needs wifi). The
dictionary popup already has an offline definition, so saving a word from
there costs no network.
]]

local ConfirmBox = require("ui/widget/confirmbox")
local InfoMessage = require("ui/widget/infomessage")
local Trapper = require("ui/trapper")
local Translator = require("ui/translator")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local json = require("json")
local lfs = require("libs/libkoreader-lfs")
local util = require("util")
local _ = require("gettext")
local T = require("ffi/util").template

local DATA_DIR = "/home/root/.majortom"
local VOCAB_FILE = DATA_DIR .. "/vocab.jsonl"

-- A selection with no spaces is a word; anything else is a phrase. Only used
-- to pick which button reads as the obvious one -- both are always offered.
local function looksLikeWord(text)
    return not text:find("%s")
end

local MajorTom = WidgetContainer:extend{
    name = "majortom",
    is_doc_only = true,
}

function MajorTom:init()
    if self.ui and self.ui.highlight then
        self.ui.highlight:addToHighlightDialog("12_majortom", function(this)
            return {
                text = _("Save to MajorTom"),
                callback = function()
                    local text = util.cleanupSelectedText(this.selected_text.text)
                    -- Read the context before closing: onClose drops the
                    -- selection, and the context is derived from it.
                    local context = self:context()
                    this:onClose()
                    self:translateThenSave(text, context)
                end,
            }
        end)
    end
    if self.ui and self.ui.dictionary then
        self.ui.dictionary:addToDictButtons({
            id = "majortom",
            menu_text = _("MajorTom"),
            text = _("Save to MajorTom"),
            insert_first = true,
            font_bold = false,
            callback = function(dict_popup)
                local word = dict_popup.lookupword
                -- The definition is already on screen and offline, so there is
                -- nothing to ask and nothing to fetch: save it straight away.
                self:save("word", word, self:firstLine(dict_popup.definition), self:context())
            end,
        })
    end
end

-- Dictionary definitions are long and often HTML. We only want a gloss; the
-- full entry stays in the dictionary where it is searchable.
function MajorTom:firstLine(definition)
    if type(definition) ~= "string" then return "" end
    local text = definition:gsub("<[^>]->", " "):gsub("%s+", " ")
    return util.trim(text):sub(1, 300)
end

function MajorTom:bookInfo()
    local props = self.ui and self.ui.doc_props or {}
    return {
        title = props.display_title or props.title or _("Unknown book"),
        author = props.authors or "",
        language = props.language or "",
    }
end

-- Pull the sentence around the selection so a saved word is never stranded
-- without the context it was met in.
function MajorTom:context()
    if not (self.ui and self.ui.highlight) then return "" end
    local ok, prev, next = pcall(self.ui.highlight.getSelectedWordContext, self.ui.highlight, 15)
    if not ok then return "" end
    return util.trim((prev or "") .. " " .. (next or ""))
end

function MajorTom:translateThenSave(text, context)
    if not text or text == "" then return end
    Trapper:wrap(function()
        local completed, translation = Trapper:dismissableRunInSubprocess(function()
            return Translator:translate(text)
        end, _("Translating…"))

        if not completed then return end

        -- No wifi, or the service failed. Saving is still worth offering: the
        -- Mac can translate it later, and losing the word is the worse outcome.
        local body = translation and (text .. "\n\n→ " .. translation)
            or T(_("%1\n\nCould not translate (no connection?). Save it anyway and translate on sync."), text)

        local word_first = looksLikeWord(text)
        local save = function(kind)
            self:save(kind, text, translation or "", context)
        end

        UIManager:show(ConfirmBox:new{
            text = body,
            ok_text = word_first and _("Save as word") or _("Save as phrase"),
            ok_callback = function() save(word_first and "word" or "phrase") end,
            other_buttons = {{
                {
                    text = word_first and _("Save as phrase") or _("Save as word"),
                    callback = function() save(word_first and "phrase" or "word") end,
                },
            }},
            cancel_text = _("Discard"),
        })
    end)
end

function MajorTom:save(kind, text, translation, context)
    local book = self:bookInfo()
    local entry = {
        kind = kind,
        text = text,
        translation = translation or "",
        context = context or "",
        page = self.ui and self.ui.getCurrentPage and self.ui:getCurrentPage() or 0,
        book = book.title,
        author = book.author,
        language = book.language,
        saved_at = os.date("!%Y-%m-%dT%H:%M:%S.000Z"),
    }

    local ok, err = self:append(entry)
    UIManager:show(InfoMessage:new{
        text = ok and T(_("Saved: %1"), text) or T(_("Could not save: %1"), err),
        timeout = 2,
    })
end

-- Append-only, one JSON object per line. Nothing here ever rewrites the file,
-- so a crash mid-write can cost the last line and nothing else.
function MajorTom:append(entry)
    if not lfs.attributes(DATA_DIR, "mode") then
        lfs.mkdir(DATA_DIR)
    end
    local encoded, err = json.encode(entry)
    if not encoded then return false, tostring(err) end

    local file = io.open(VOCAB_FILE, "a")
    if not file then return false, _("cannot open file") end
    file:write(encoded .. "\n")
    file:close()
    return true
end

return MajorTom
