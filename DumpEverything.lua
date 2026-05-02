require 'HelperFunctions'
require 'SaveFunctions'

-- This script automates extracting data, images, animations, and audio files from .wz files.
-- It has been specifically tested with MapleStory Classic World's Closed Online Test client, but may work with other clients as well.

-- Note on exporting animation frames: the game uses "Wz_Uol" to reuse existing frames, so while only 3 images might export for animation "walk", the  animation might also reuse 2 frames from the "stand" animation. Check Npc\0000406.img\smile in WzComparer for an example.

-- TODO: Support Character.wz animations. Requires stitching body parts together for each frame, and different tree traversal logic (frame indices are directories instead of PNGs. Inside the directory there are PNGs for body and arm and a node for frame delay). See isDelayNode in HelperFunctions.
-- TODO: Handle animations with no delay (Effect\BasicEff.img\LevelUp)

------------------------------------------------------------
-- Config

outputDir = "D:\\wz"
local rootWzName = "Npc\\0000406.img" -- Use "Base" to dump all .wz files

-- Export options. Set to nil to avoid exporting.
local imageOutputFileType = "png"     -- "png"/nil
local animationOutputFileType = "gif" -- "apng"/"gif"/nil
local audioOutputFileType = nil     -- "mp3"/"wav"/nil
local dataOutputFileType = "json"      -- "xml"/nil
-- Fonts currently not supported

-- Setting this to true will prioritize saving animations first, and only save static images if they are not part of an animation.
-- Requires a valid imageOutputFileType and animationOutputFileType.
local preferAnimations = false

------------------------------------------------------------
-- Main

errorList = {}
savedAnimations = {}
failedAnimations = {}
local rootWz = findWz(rootWzName)

if not rootWz then
    env:WriteLine('"{0}" not loaded.', rootWzName)
    return
end

local imageSaveFuncs = {
    ["png"] = savePng
}

local animationSaveFuncs = {
    ["apng"] = saveApng,
    ["gif"] = saveGif
}

local audioSaveFuncs = {
    ["mp3"] = saveMp3,
    ["wav"] = saveWav
}

local dataSaveFuncs = {
    ["xml"] = saveXml,
    ["json"] = saveJson
}

local imageSaveFunc = imageSaveFuncs[imageOutputFileType]
local animationSaveFunc = animationSaveFuncs[animationOutputFileType]
local audioSaveFunc = audioSaveFuncs[audioOutputFileType]
local dataSaveFunc = dataSaveFuncs[dataOutputFileType]

if not imageSaveFunc and not animationSaveFunc and not audioSaveFunc and not dataSaveFunc then
    env:WriteLine("No supported file types provided.")
    return
end

local DateTime = luanet.import_type('System.DateTime')
local startTime = DateTime.Now

-- Deeply traverses virtual filesystem for directories
for wzNode in enumAllWzNodes(rootWz) do
    local wzImg = Wz_NodeExtension.GetNodeWzImage(wzNode) -- Wz_Image is basically a directory
    if wzImg then
        env:WriteLine('(extract) ' .. wzNode.FullPathToFile)

        local saveFolder = Path.Combine(outputDir, toValidPath(removeCanvasFromPath(wzNode.FullPathToFile)))

        if not Directory.Exists(saveFolder) then
            Directory.CreateDirectory(saveFolder)
        end

        local ok, err = pcall(function()
            if not wzImg:TryExtract() then
                logError(string.format("Extract failed: %s", wzImg.Name))
                return
            end

            for node in enumAllWzNodes(wzImg.Node) do
                -- This is simply kept as reference; Apng/Gif builders already handle Uol
                -- if isUolNode(node) then
                --     node = node.Value:HandleUol(node)
                -- end

                if animationSaveFunc and isDelayNode(node) then
                    local folderPath = node.ParentNode.ParentNode.FullPathToFile

                    -- Since all frames use the same parent folder, only try saving animation on the first frame and skip subsequent frames
                    if not savedAnimations[folderPath] and not failedAnimations[folderPath] then
                        local saveOk, saveErr = pcall(animationSaveFunc, node, saveFolder, animationOutputFileType)
                        if saveOk then
                            savedAnimations[folderPath] = true
                        else
                            failedAnimations[folderPath] = true
                            logError(string.format("Error saving [%s]: %s", node.FullPathToFile, saveErr))
                        end
                    end
                end

                if imageSaveFunc and isPngNode(node) then
                    local skip = preferAnimations and savedAnimations[node.ParentNode.FullPathToFile]
                    if not skip then
                        trySave(imageSaveFunc, node, saveFolder)
                    end
                end

                if audioSaveFunc and isSoundNode(node) then
                    trySave(audioSaveFunc, node, saveFolder)
                end
            end

            -- Skip checking _Canvas directories for data
            if dataSaveFunc and not isCanvasDir(wzNode.FullPathToFile) then
                -- Go up 1 directory to put data alongside .img folder
                saveFolder = Path.GetDirectoryName(saveFolder)
                trySave(dataSaveFunc, wzNode, saveFolder, wzImg)
            end

            wzImg:Unextract()
        end)

        if not ok then
            logError(string.format("Unexpected error in Wz_Image [%s]: %s", wzImg.Name, err))
        end
    end
end

if #errorList > 0 then
    env:WriteLine("-------- Error Summary --------")
    for _, err in ipairs(errorList) do
        env:WriteLine(err)
    end
end

local elapsed = DateTime.Now - startTime
env:WriteLine(string.format("-------- Done in %d:%02d:%02d --------", elapsed.Hours, elapsed.Minutes, elapsed.Seconds))
