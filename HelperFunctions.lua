import 'WzComparerR2.PluginBase'
import 'WzComparerR2.WzLib'
import 'WzComparerR2.Common'
import 'WzComparerR2.Encoders'
import 'System.IO'
import 'System.Xml'
import 'System.Drawing, Version=4.0.0.0, Culture=neutral, PublicKeyToken=b03f5f7f11d50a3a'
import 'System.Drawing'
import 'System.Drawing.Imaging'
import 'System.Text'

function isWzImage(value)
    return value and type(value) == "userdata" and
        (value:GetType().Name == 'Wz_Image' or value:GetType().Name == 'Ms_Image' or value:GetType().Name ==
            'Ms_ImageV2')
end

function enumAllWzNodes(node)
    return coroutine.wrap(function()
        coroutine.yield(node)
        for _, v in each(node.Nodes) do
            for child in enumAllWzNodes(v) do
                coroutine.yield(child)
            end
        end
    end)
end

local ivPattern
do
    local p = Path.GetInvalidFileNameChars()
    local ivStr = ""
    for _, v in each(p) do
        if v >= 32 then
            ivStr = ivStr .. string.char(v)
        end
    end
    ivPattern = "[" .. ivStr .. "]"
end

-- Replaces invalid path characters with periods
function toValidFileName(fileName)
    return fileName:gsub(ivPattern, ".")
end

-- Replaces invalid path characters with periods in each section (between slashes) in a path
function toValidPath(filePath)
    local segments = {}
    for segment in filePath:gmatch("[^\\]+") do
        segments[#segments + 1] = toValidFileName(segment)
    end
    return table.concat(segments, "\\")
end

-- Sheds the first part of a node.FullPath (removes the .img section)
function fullPathToFileName(fullPath)
    return toValidFileName(fullPath:sub(fullPath:find("\\") + 1))
end

-- Deletes the "_Canvas" section of a file path
function removeCanvasFromPath(path)
    return path:gsub("\\_Canvas", "")
    -- return path:gsub("\\[_][^\\]*", "") -- Remove anything prefixed with _
end

function logError(msg)
    env:WriteLine(msg)
    table.insert(errorList, msg)
end

function findWz(path)
    return PluginManager.FindWz(path)
end

------------------------------------------------------------
-- Type checks

function isPngNode(node)
    return node.Value and type(node.Value) == "userdata" and node.Value:GetType().Name == 'Wz_Png'
end

function isDelayNode(node)
    -- Temp fix: ignore delay nodes if their parent isn't a Wz_Png (like in Effect.wz) or named a number.
    -- Need to refactor for Character.wz which sometimes houses delay as a sibling node to the Wz_Png frames, or has non-number frame names.
    return node.Text == "delay" and node:GetType().Name == 'Wz_Node' and isPngNode(node.ParentNode) and tonumber(node.ParentNode.Text)
end

function isSoundNode(node)
    -- Fonts are listed as Type: Wz_Sound for some reason (Etc/NANUMGOTHIC.img, ...)
    return node.Value and type(node.Value) == "userdata" and node.Value:GetType().Name == 'Wz_Sound' and node.Text ~=
        "FONT_DATA"
end

function isCanvasDir(dir)
    return string.find(dir, "_Canvas")
end

function isVectorNode(node)
    return node.Value and type(node.Value) == "userdata" and node.Value:GetType().Name == 'Wz_Vector'
end

function isUolNode(node)
    return node.Value and type(node.Value) == "userdata" and node.Value:GetType().Name == "Wz_Uol"
end