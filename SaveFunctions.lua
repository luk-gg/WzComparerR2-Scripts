function trySave(saveFunc, node, saveFolder, ...)
    local saveOk, saveErr = pcall(saveFunc, node, saveFolder, ...)
    if not saveOk then
        logError(string.format("Error saving [%s]: %s", node.FullPathToFile, saveErr))
    end
end

------------------------------------------------------------
-- Animations

-- Ensures that animation frames are indexed from 0 as expected in saveApng. Does NOT address frame index gaps in numbers beyond 0 (i.e. if PNG indices are [0, 1, 3, 4]) to avoid falsely adjusting frame sequence.
function repairFrameIndices(folderNode)
    local pngIndex = nil
    for _, frame in each(folderNode.Nodes) do
        if isPngNode(frame) or isUolNode(frame) then
            local frameNum = tonumber(frame.Text)
            if frameNum == 0 then
                break
            end

            pngIndex = pngIndex and pngIndex + 1 or 0

            if frameNum and frameNum > pngIndex then
                env:WriteLine("Repairing frame sequence for " .. folderNode.FullPathToFile .. " (node text: " ..
                    frameNum .. ", actual index: " .. pngIndex .. ")")
                frame.Text = tostring(pngIndex)
            end
        end
    end
end

-- IGifFrame.Draw is an interface method; LuaInterface requires a cached method handle to dispatch it correctly.
local t_IGifFrame = {}
t_IGifFrame.typeRef = luanet.import_type('WzComparerR2.Common.IGifFrame')
t_IGifFrame.Draw = luanet.get_method_bysig(t_IGifFrame.typeRef, 'Draw', "System.Drawing.Graphics",
    "System.Drawing.Rectangle")

-- WzComparerR2.Common/Encoders provides BuildInApngEncoder and BuildInGifEncoder; the rest of the logic is nearly identical.
function saveAnimation(node, saveFolder, ext, createEncoder)
    local delayNode = node -- Etc\RuneStone.img\runeStone\0\0\stay\0\delay
    local pngNode = delayNode.ParentNode
    local folderNode = pngNode.ParentNode

    local fileName = fullPathToFileName(folderNode.FullPath)
    local filePath = Path.Combine(saveFolder, fileName .. ext)

    repairFrameIndices(folderNode)

    local gif = Gif.CreateFromNode(folderNode, findWz)
    if not gif then
        error("Gif.CreateFromNode returned nil — animation may be missing frame 0")
    end
    local rect = gif:GetRect()

    local enc = createEncoder(filePath, rect.Width, rect.Height)

    for _, frame in each(gif.Frames) do
        local bmp = Bitmap(rect.Width, rect.Height, PixelFormat.Format32bppArgb)
        local g = Graphics.FromImage(bmp)
        t_IGifFrame.Draw(frame, g, rect)
        g:Dispose()
        enc:AppendFrame(bmp, frame.Delay)
        bmp:Dispose()
    end

    enc:Dispose()

    for _, frame in each(gif.Frames) do
        frame.Bitmap:Dispose()
    end
end

function saveApng(node, saveFolder)
    saveAnimation(node, saveFolder, ".apng", function(filePath, w, h)
        local enc = BuildInApngEncoder()
        enc:Init(filePath, w, h)
        enc.OptimizeEnabled = false
        return enc
    end)
end

function saveGif(node, saveFolder)
    saveAnimation(node, saveFolder, ".gif", function(filePath, w, h)
        local enc = BuildInGifEncoder()
        enc:Init(filePath, w, h)
        return enc
    end)
end

------------------------------------------------------------
-- Images

function savePng(node, saveFolder)
    local fileName = fullPathToFileName(node.FullPath)
    local filePath = Path.Combine(saveFolder, fileName .. ".png")
    local png = node.Value

    -- Must have a valid size otherwise it exports 1x1 blank images
    if not (png.Width > 1 or png.Height > 1) then
        return
    end
    local bmp = png:ExtractPng()
    if not bmp then
        error("ExtractPng() returned nil.")
    end
    bmp:Save(filePath)
    bmp:Dispose()
end

------------------------------------------------------------
-- Audio

function saveMp3(node, saveFolder)
    local fileName = fullPathToFileName(node.FullPath)
    local filePath = Path.Combine(saveFolder, fileName .. ".mp3")

    local sound = node.Value
    if not sound.SoundType == Wz_SoundType.Mp3 then
        error(string.format("Skipping incompatible audio file [%s]: %s", node.FullPathToFile))
        return
    end
    File.WriteAllBytes(filePath, sound:ExtractSound())
end

function saveWav(node, saveFolder)
    local fileName = fullPathToFileName(node.FullPath)
    local filePath = Path.Combine(saveFolder, fileName .. ".wav")

    local sound = node.Value
    if not sound.SoundType == Wz_SoundType.Pcm then
        error(string.format("Skipping incompatible audio file [%s]: %s", node.FullPathToFile))
        return
    end
    File.WriteAllBytes(filePath, sound:ExtractSound())
end

------------------------------------------------------------
-- Data

function saveXml(node, saveFolder, wzImg)
    local fileName = toValidFileName(Path.GetFileName(node.FullPath))
    local filePath = Path.Combine(saveFolder, fileName .. ".xml")

    local file = File.Create(filePath)
    local settings = XmlWriterSettings()
    settings.CloseOutput = true
    settings.Indent = true
    settings.Encoding = Encoding.UTF8
    settings.CheckCharacters = false
    settings.NewLineChars = "\r\n"
    settings.NewLineHandling = NewLineHandling.None
    settings.NewLineOnAttributes = false

    local writer = XmlWriter.Create(file, settings)

    writer:WriteStartDocument(true);
    Wz_NodeExtension.DumpAsXml(wzImg.Node, writer)
    writer:WriteEndDocument()

    writer:Flush()
    file:Close()
end

-- Vibecoded JSON saving
local function isArray(t)
    local i = 0
    for _ in pairs(t) do
        i = i + 1
        if t[i] == nil then return false end
    end
    return true
end

local function toJson(val, indent, depth)
    indent = indent or "    "
    depth = depth or 0
    local pad = string.rep(indent, depth)
    local padInner = string.rep(indent, depth + 1)

    if type(val) == "table" then
        if isArray(val) then
            local parts = {}
            for _, v in ipairs(val) do
                parts[#parts + 1] = padInner .. toJson(v, indent, depth + 1)
            end
            return "[\n" .. table.concat(parts, ",\n") .. "\n" .. pad .. "]"
        else
            local parts = {}
            for k, v in pairs(val) do
                if v ~= nil then
                    parts[#parts + 1] = padInner .. '"' .. tostring(k) .. '": ' .. toJson(v, indent, depth + 1)
                end
            end
            return "{\n" .. table.concat(parts, ",\n") .. "\n" .. pad .. "}"
        end
    elseif type(val) == "number" then
        return tostring(val)
    elseif type(val) == "boolean" then
        return tostring(val)
    elseif val == nil then
        return "null"
    else
        local s = tostring(val):gsub('\\', '\\\\'):gsub('"', '\\"'):gsub('\n', '\\n'):gsub('\r', '\\r')
        return '"' .. s .. '"'
    end
end

local function wzNodeToTable(node)
    local result = {}

    if node.Nodes.Count == 0 then
        if isVectorNode(node) then
            return { x = node.Value.X, y = node.Value.Y }
        end

        if isUolNode(node) then
            return node.Value.Uol
        end

        return node.Value
    end

    for _, child in each(node.Nodes) do
        result[child.Text] = wzNodeToTable(child)
    end

    if node.Value then
        result["__type"] = node.Value:GetType().Name
    end

    return result
end

function saveJson(node, saveFolder, wzImg)
    local fileName = toValidFileName(Path.GetFileName(node.FullPath))
    local filePath = Path.Combine(saveFolder, fileName .. ".json")

    local data = wzNodeToTable(wzImg.Node)
    local json = toJson(data)
    File.WriteAllText(filePath, json)
end
