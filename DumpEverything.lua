require 'HelperFunctions'
require 'SaveFunctions'

-- TODO: Support Character.wz animations. Requires stitching body parts together for each frame, and different tree traversal logic (Character.wz has delay in walk\0 and PNGs in walk\0\body and walk\0\arm). See "Temp fix" below.
-- TODO: Cleanup unused folders

------------------------------------------------------------
-- Config

outputDir = "D:\\wz"
local rootWzName = "Base" -- Use "Base" to dump all .wz files

-- Export options. Set to nil to avoid exporting.
local imageOutputFileType = "png"       -- "png"/nil
local animationOutputFileType = "apng" -- "apng"/"gif"/nil
local audioOutputFileType = "mp3"       -- "mp3"/"wav"/nil
local dataOutputFileType = "json"     -- "xml"/nil
-- Fonts currently not supported

-- Setting this to true will prioritize saving animations first, and only save static images if they are not part of an animation.
-- Requires a valid imageOutputFileType and animationOutputFileType.
local preferAnimations = false

-- Setting this to true will put all images and animations in the same folder, removing the _Canvas folder which only stores images. Data files with fields containing "_Canvas" will also be adjusted. If set to false, PNGs will be in _Canvas\.img while animations will be in .img folders.
flattenCanvasFolder = true

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

        local saveFolder = Path.Combine(outputDir, toValidPath(wzNode.FullPathToFile))
        if flattenCanvasFolder then
            saveFolder = Path.Combine(outputDir, toValidPath(removeCanvasFromString(wzNode.FullPathToFile)))
        end

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

                -- Temp fix: use tonumber() to ignore PNGs that aren't numbers (Character.wz)
                if animationSaveFunc and isPngNode(node) and tonumber(node.Text) and not isCanvasDir(wzNode.FullPathToFile) then
                    local folderNode = node.ParentNode

                    -- Check if its a single frame or has multiple frames
                    if isAnimationFolder(folderNode) then
                        local folderPath = folderNode.FullPathToFile

                        -- Since all frames use the same parent folder, only try saving animation on the first frame and skip subsequent frames
                        if not savedAnimations[folderPath] and not failedAnimations[folderPath] then
                            local saveOk, saveErr = pcall(animationSaveFunc, node, saveFolder,
                                animationOutputFileType)
                            if saveOk then
                                savedAnimations[folderPath] = true
                            else
                                failedAnimations[folderPath] = true
                                logError(string.format("Error saving [%s]: %s", node.FullPathToFile, saveErr))
                            end
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
                local dataSaveFolder = Path.GetDirectoryName(saveFolder)
                trySave(dataSaveFunc, wzNode, dataSaveFolder, wzImg)
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
