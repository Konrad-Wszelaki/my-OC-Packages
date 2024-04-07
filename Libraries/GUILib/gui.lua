-- TODO:
--      - continue developing the bar graph: add a way of adding, removing and replacing data

local component     = require("component")
local gpu           = component.gpu
local event         = require("event")
local keyboard      = require("keyboard")
local io            = require("io")
local thread        = require("thread")

local kwlib         = require("KWLib")





-- actual library starts here
local GUI = {}
GUI.VERSION_MAJOR = "2"
GUI.VERSION_MINOR = "1"

GUI.KWLIB_VERSION_MAJOR = "2"
GUI.KWLIB_VERSION_MINOR = "1"
-- check if the KWLIB version is compatible with this library
if kwlib:checkVersionCompat(GUI.KWLIB_VERSION_MAJOR, GUI.KWLIB_VERSION_MINOR) == false then
    error("KWLIB version is incompatible with the GUI library, cannot proceed...")
end

GUI.WIDTH, GUI.HEIGHT = gpu.getResolution()
GUI.objects = {}
GUI.objects[1] = {type = "GUI"}
GUI.eventHandlers = {}
GUI.eventHandlers[1] = {eventID = "VOID"}
GUI.running = false
GUI.focusedTextInputID = nil
GUI.lastObjectPressed = nil
GUI.focusedCustomObjectID = nil
GUI.redrawOnTick = true
GUI.ticksPerRedraw = 1
GUI.ticksSinceRedraw = 0
GUI.tickRate = 2

-- define all the colors
GUI.colors = {
    COLOR_general_bg = 0x000000,
    COLOR_general_fg = 0xFFFFFF,

    COLOR_success_bg = 0x00FF00,
    COLOR_success_fg = 0xFFFFFF,

    COLOR_warning_bg = 0x999900,
    COLOR_warning_fg = 0x000000,

    COLOR_alarm_bg   = 0xFF0000,
    COLOR_alarm_fg   = 0xFFFFFF,

    COLOR_list_bg_A = 0x000077,
    COLOR_list_bg_B = 0x007777,
    COLOR_list_fg   = 0xFFFF00,
    COLOR_list_scroll_active_bg   = 0x007700,
    COLOR_list_scroll_inactive_bg = 0x444444,
    COLOR_list_scroll_fg          = 0xFFFFFF,

    COLOR_button_fg = 0xFFFFFF,
    COLOR_button_inactive_bg = 0x444444,
    COLOR_button_active_bg = 0x000000,
    COLOR_button_hover_bg = 0x777700,
    COLOR_button_pressed_bg = 0x990000
}

-- define useful symbols
GUI.symbols = {
    SYM_vertical_bar_slim  = "│",
    SYM_vertical_bar_thick = "║",

    SYM_horizontal_bar_slim  = "─",
    SYM_horizontal_bar_thick = "═",

    SYM_upper_left_corner_slim  = "┌",
    SYM_upper_left_corner_thick = "╔",
    SYM_upper_right_corner_slim  = "┐",
    SYM_upper_right_corner_thick = "╗",
    SYM_lower_left_corner_slim  = "└",
    SYM_lower_left_corner_thick = "╚",
    SYM_lower_right_corner_slim  = "┘",
    SYM_lower_right_corner_thick = "╝",

    SYM_up_t_slim     = "┬",
    SYM_down_t_slim   = "┴",
    SYM_left_t_slim   = "├",
    SYM_right_t_slim  = "┤",
    SYM_up_t_thick    = "╦",
    SYM_down_t_thick  = "╩",
    SYM_left_t_thick  = "╠",
    SYM_right_t_thick = "╣",

    SYM_x_slim  = "┼",
    SYM_x_thick = "╬",

    SYM_full_block  = "█",

    SYM_seven_eights_lower_block = "▇",
    SYM_three_quarters_lower_block = "▆",
    SYM_five_eights_lower_block = "▅",
    SYM_lower_block = "▄",
    SYM_three_eights_lower_block = "▃",
    SYM_one_quarter_lower_block = "▂",
    SYM_one_eight_lower_block = "▁",
    SYM_upper_block = "▀",

    SYM_seven_eights_left_block = "▉",
    SYM_three_quarters_left_block = "▊",
    SYM_five_eights_left_block = "▋",
    SYM_half_left_block = "▌",
    SYM_three_eights_left_block = "▍",
    SYM_one_quarter_left_block = "▎",
    SYM_one_eight_left_block = "▏",
    SYM_half_right_block = "▐",

    SYM_left_pointers   = "«",
    SYM_right_pointers  = "»",
    SYM_left_arrowhead  = "˂",
    SYM_right_arrowhead = "˃",
    SYM_up_arrowhead = "˄",
    SYM_down_arrowhead = "˅",

    SYM_caret = "*",
}

GUI.map = kwlib.general.map

function GUI.version(self)
    return self.VERSION_MAJOR .. "." .. self.VERSION_MINOR
end

function GUI.versionMinor(self)
    return self.VERSION_MINOR
end

function GUI.versionMajor(self)
    return self.VERSION_MAJOR
end

function GUI.checkVersionCompat(self, versionMajor, versionMinor)
    if tonumber(versionMajor) ~= tonumber(self.VERSION_MAJOR) then
        io.write("GUI major version mismatch, make sure the version is compatible with this script!")
        return false
    end
    if tonumber(versionMinor)  > tonumber(self.VERSION_MINOR) then
        io.write("GUI minor version older than required, make sure the version is compatible with this script!")
        return false
    end
    return true
end

function GUI.clearScreen(self)
    gpu.setBackground(self.colors.COLOR_general_bg)
    gpu.setForeground(self.colors.COLOR_general_fg)
    gpu.fill(1, 1, self.WIDTH, self.HEIGHT, " ")

    return true
end

function GUI.drawSlimBorder(self, x, y, w, h, title)
    --gpu.fill(x, y, w, h, " ")

    gpu.fill(x, y, w, 1, self.symbols.SYM_horizontal_bar_slim)
    gpu.fill(x, y, 1, h, self.symbols.SYM_vertical_bar_slim)
    gpu.fill(x, y+(h-1), w, 1, self.symbols.SYM_horizontal_bar_slim)
    gpu.fill(x+(w-1), y, 1, h, self.symbols.SYM_vertical_bar_slim)

    gpu.set(x, y, self.symbols.SYM_upper_left_corner_slim)
    gpu.set(x+(w-1), y, self.symbols.SYM_upper_right_corner_slim)
    gpu.set(x, y+(h-1), self.symbols.SYM_lower_left_corner_slim)
    gpu.set(x+(w-1), y+(h-1), self.symbols.SYM_lower_right_corner_slim)

    if type(title) == string then
        if string.len(title) <= w-4 then
            local offset = math.floor((w-string.len(title))/2)
            gpu.set(x+offset-1, y, self.symbols.SYM_right_t_slim)
            gpu.set(x+offset, y, title)
            gpu.set(x+offset+string.len(title), y, self.symbols.SYM_left_t_slim)
        end
    end

    return true
end

function GUI.drawThickBorder(self, x, y, w, h, title)
    --gpu.fill(x, y, w, h, " ")

    gpu.fill(x, y, w, 1, self.symbols.SYM_horizontal_bar_thick)
    gpu.fill(x, y, 1, h, self.symbols.SYM_vertical_bar_thick)
    gpu.fill(x, y+(h-1), w, 1, self.symbols.SYM_horizontal_bar_thick)
    gpu.fill(x+(w-1), y, 1, h, self.symbols.SYM_vertical_bar_thick)

    gpu.set(x, y, self.symbols.SYM_upper_left_corner_thick)
    gpu.set(x+(w-1), y, self.symbols.SYM_upper_right_corner_thick)
    gpu.set(x, y+(h-1), self.symbols.SYM_lower_left_corner_thick)
    gpu.set(x+(w-1), y+(h-1), self.symbols.SYM_lower_right_corner_thick)

    if type(title) == string then
        if string.len(title) <= w-4 then
            local offset = math.floor((w-string.len(title))/2)
            gpu.set(x+offset-1, y, self.symbols.SYM_right_t_thick)
            gpu.set(x+offset, y, title)
            gpu.set(x+offset+string.len(title), y, self.symbols.SYM_left_t_thick)
        end
    end

    return true
end

function GUI.drawBorder(self, x, y, w, h, style, title)
    if style == "slim" then
        self:drawSlimBorder(x, y, w, h, title)
        return true
    elseif style == "thick" then
        self:drawThickBorder(x, y, w, h, title)
        return true
    end
    return false
end

function GUI.drawBorderAndGetDimensions(self, objects, ID)
    local x = objects[ID].x
    local y = objects[ID].y
    local w = objects[ID].w
    local h = objects[ID].h

    if objects[ID].borderStyle == "slim" or objects[ID].borderStyle == "thick" then
        self:drawBorder(objects[ID].x, objects[ID].y, objects[ID].w, objects[ID].h, objects[ID].borderStyle, objects[ID].title)
        x = x + 1
        y = y + 1
        w = w - 2
        h = h - 2
    end

    return x, y, w, h
end

function GUI.clearArea(self, x, y, w, h)
    gpu.fill(x, y, w, h, " ")
end

function GUI.checkIfWithinObjectBoundary(self, xPos, yPos, object)
    return xPos >= object.x and xPos < (object.x + object.w) and yPos >= object.y and yPos < (object.y + object.h)
end

function GUI.drawSelectList(self, objects, ID)
    if objects[ID].visible == true then
        gpu.setBackground(self.colors.COLOR_general_bg)
        gpu.setForeground(self.colors.COLOR_general_fg)

        local x, y, w, h = self:drawBorderAndGetDimensions(objects, ID)

        if objects[ID].scrollable == true then
            if objects[ID].position > 1 then
                gpu.setBackground(self.colors.COLOR_list_scroll_active_bg)
                objects[ID].upScrollActive = true
            else
                gpu.setBackground(self.colors.COLOR_list_scroll_inactive_bg)
                objects[ID].upScrollActive = false
            end
            gpu.setForeground(self.colors.COLOR_list_scroll_fg)
            gpu.set(x + math.floor((w-string.len(objects[ID].upText))/2), y, objects[ID].upText)


            if #objects[ID].items - (objects[ID].position - 1) > (h-2) then
                gpu.setBackground(self.colors.COLOR_list_scroll_active_bg)
                objects[ID].downScrollActive = true
            else
                gpu.setBackground(self.colors.COLOR_list_scroll_inactive_bg)
                objects[ID].downScrollActive = false
            end
            gpu.set(x + math.floor((w-string.len(objects[ID].downText))/2), y+(h-1), objects[ID].downText)

            y = y + 1
            h = h - 2
        end

        local imax = #objects[ID].items
        if imax > h then imax = h end
        gpu.setForeground(self.colors.COLOR_list_fg)
        for i = 0, imax-1 do
            if (objects[ID].position+i)%2 == 1 then
                gpu.setBackground(self.colors.COLOR_list_bg_A)
            else
                gpu.setBackground(self.colors.COLOR_list_bg_B)
            end

            if (objects[ID].position+i) == objects[ID].selected_item then
                gpu.setBackground(self.colors.COLOR_button_pressed_bg)
            end

            self:clearArea(x, y+i, w, 1)
            gpu.set(x, y+i, string.sub(objects[ID].items[objects[ID].position + i].content, 1, w))
        end

        return true
    end

    return false
end

function GUI.drawOneLineTextField(self, objects, ID)
    if objects[ID].visible == true then
        local outputText = objects[ID].value
        gpu.setForeground(self.colors.COLOR_general_fg)
        if objects[ID].focused then
            gpu.setBackground(self.colors.COLOR_warning_bg)
            if objects[ID].position == 1 then
                outputText = objects[ID].caret_symbol .. outputText
            else
                outputText = string.sub(objects[ID].value, 1, objects[ID].position - 1) .. objects[ID].caret_symbol .. string.sub(objects[ID].value, objects[ID].position, string.len(objects[ID].value))
            end
        else
            gpu.setBackground(self.colors.COLOR_general_bg)
        end

        self:clearArea(objects[ID].x, objects[ID].y, objects[ID].w, objects[ID].h)
        gpu.set(objects[ID].x, objects[ID].y, string.sub(outputText, 1, objects[ID].w))

        return true
    end
    return false
end

function GUI.drawText(self, objects, ID)
    local x, y, w, h = self:drawBorderAndGetDimensions(objects, ID)
    local outputText = objects[ID].value

    self:clearArea(x, y, w, h)
    if type(outputText) ~= "table" then
        if string.len(outputText) > w then
            local excess_len_left_side = math.floor((string.len(outputText) - w)/2)
            local excess_len_right_side = math.ceil((string.len(outputText) - w)/2)
            outputText = string.sub(outputText, excess_len_left_side, string.len(outputText) - excess_len_right_side)
        end
        gpu.set(x + math.floor((w-string.len(outputText))/2), y, outputText)
    else
        for i, substring in pairs(outputText) do
            gpu.set(x, y + i - 1, substring)
        end
    end

    return true
end

function GUI.drawInfoBox(self, objects, ID)
    local result = self:drawText(objects, ID)
    return self:drawButton(objects[ID].content, objects[ID].content.ID) and result
end

function GUI.drawButton(self, objects, ID)
    if objects[ID].visible == true then
        gpu.setForeground(objects[ID].fgcolor)
        if objects[ID].active == false then
            gpu.setBackground(objects[ID].inactivebgcolor)
        elseif objects[ID].pressed == false then
            gpu.setBackground(objects[ID].activegbcolor)
        else
            gpu.setBackground(objects[ID].pressedbgcolor)
        end

        return self:drawText(objects, ID)
    end
    return false
end

function GUI.drawLabel(self, objects, ID)
    if objects[ID].visible == true then
        gpu.setForeground(self.colors.COLOR_general_fg)
        gpu.setBackground(self.colors.COLOR_general_bg)

        return self:drawText(objects, ID)
    end
    return false
end

function GUI.chooseEndSymbolForBar(self, value, scale)
    local excess = (value/scale)
    if excess >= 1    then 
        if value > 0 then   return self.symbols.SYM_full_block 
        else                return " "            
        end
    end
    if excess > (7/8) then 
        if value > 0 then   return self.symbols.SYM_seven_eights_lower_block    
        else                return self.symbols.SYM_one_eight_lower_block            
        end
    end
    if excess > (3/4) then 
        if value > 0 then   return self.symbols.SYM_three_quarters_lower_block 
        else                return self.symbols.SYM_one_quarter_lower_block          
        end
    end
    if excess > (5/8) then 
        if value > 0 then   return self.symbols.SYM_five_eights_lower_block
        else                return self.symbols.SYM_three_eights_lower_block            
        end 
    end
    if excess > (1/2) then return self.symbols.SYM_lower_block end             
    if excess > (3/8) then 
        if value > 0 then   return self.symbols.SYM_three_eights_lower_block 
        else                return self.symbols.SYM_five_eights_lower_block            
        end
    end
    if excess > (1/4) then 
        if value > 0 then   return self.symbols.SYM_one_quarter_lower_block 
        else                return self.symbols.SYM_three_quarters_lower_block            
        end 
    end
    if excess > (1/8) then 
        if value > 0 then   return self.symbols.SYM_one_eight_lower_block 
        else                return self.symbols.SYM_seven_eights_lower_block            
        end 
    end
    if value >= 0 then      return " "
    else                    return self.symbols.SYM_full_block 
    end
end

function GUI.drawBarGraph(self, objects, ID)
    if objects[ID].visible == true and objects[ID].redraw == true then
        gpu.setBackground(self.colors.COLOR_general_bg)
        gpu.setForeground(objects[ID].fgColor)

        local x, y, w, h = self:drawBorderAndGetDimensions(objects, ID)

        self:clearArea(x, y, w, h)

        local yLims = objects[ID].yLims
        local xLims = objects[ID].xLims

        local data = objects[ID].data.getData()
        local xData = {}
        local yData = {}
        for i = 1, #data do
            xData[i] = data[i][1]
            yData[i] = data[i][2]
        end
        data = nil
        if objects[ID].autoYLims then
            yLims[1] = 1.1 * math.min(yData)
            yLims[2] = 1.1 * math.max(yData)
        end
        if objects[ID].autoXLims then
            xLims[1] = 1.05 * math.min(xData)
            xLims[2] = 1.05 * math.max(xData)
        end

        -- map 0-values from the graph coordinates to screen coordinates
        local xAxisYPos = math.floor(self.map(kwlib, 0, yLims, {y, (y+h)-1}))
        local yAxisXPos = math.floor(self.map(kwlib, 0, xLims, {x, (x+w)-1}))

        -- if axis positions are outside of the available space, put them at the edge
        if xAxisYPos < y+1 then
            xAxisYPos = y+1
        end
        if xAxisYPos > (y+h)-2 then
            xAxisYPos = (y+h)-2
        end
        if yAxisXPos < x+1 then
            yAxisXPos = x+1
        end
        if yAxisXPos > x+w-2 then
            yAxisXPos = (x+w)-2
        end
        
        --draw the graph
        -- first, the axis lines
        gpu.fill(x, xAxisYPos, w-1, 1, self.symbols.SYM_horizontal_bar_slim)
        gpu.fill(yAxisXPos, y+1, 1, h-2, self.symbols.SYM_vertical_bar_slim)
        -- then graph contents
        -- find graph border coordinates
        local graphStartX = x+1
        if yAxisXPos == graphStartX then graphStartX = graphStartX + 1 end
        local graphEndX = (x+w)-2
        if yAxisXPos == graphEndX then graphEndX = graphEndX - 1 end
        local graphStartY = y+1
        if xAxisYPos == graphStartY then graphStartY = graphStartY + 1 end
        local graphEndY = (y+h)-2
        if xAxisYPos == graphEndY then graphEndY = graphEndY - 1 end
        -- calculate x and y values per screen character
        local xScale = (xLims[2] - xLims[1]) / (graphEndX - graphStartX)
        local yScale = (yLims[2] - yLims[1]) / (graphEndY - graphStartY)

        local datumXPos = -1
        for i = 1, #xData do
            -- first, check if we have moved across the screen at all
            if math.floor(self.map(kwlib, xData[i], xLims, {graphStartX, graphEndX})) ~= datumXPos then
                datumXPos = math.floor(self.map(kwlib, xData[i], xLims, {graphStartX, graphEndX}))
                -- then, check if we are within the graph area
                if datumXPos >= graphStartX and datumXPos <= graphEndX then
                    -- and finally, draw the bar
                    local datumY = yData[i]
                    if yLims[1] > 0 and datumY > yLims[1] then
                        gpu.set(datumXPos, xAxisYPos, self.symbols.SYM_upper_block)
                        datumY = datumY - (yScale * 0.5)
                        if datumY > yLims[1] then
                            local datumYPos = math.floor(self.map(kwlib, datumY, yLims, {graphEndY, graphStartY})) + 1
                            if datumYPos < graphStartY then
                                gpu.fill(datumXPos, xAxisYPos - 1, 1, (xAxisYPos - 1) - graphStartY, self.symbols.SYM_full_block)
                            else
                                if datumYPos < graphEndY then
                                    gpu.fill(datumXPos, xAxisYPos - 1, 1, (xAxisYPos - 1) - datumYPos, self.symbols.SYM_full_block)
                                    datumY = datumY - (yScale * ((xAxisYPos - 1) - datumYPos))
                                end
                                gpu.set(datumXPos, datumYPos-1, self:chooseEndSymbolForBar(datumY, yScale))
                            end
                        end
                    elseif yLims[2] < 0 and datumY < yLims[2] then
                        gpu.set(datumXPos, xAxisYPos, self.symbols.SYM_lower_block)
                        datumY = datumY + (yScale * 0.5)
                        if datumY < yLims[2] then
                            local datumYPos = math.floor(self.map(kwlib, datumY, yLims, {graphEndY, graphStartY}))
                            if datumYPos > graphEndY then
                                gpu.fill(datumXPos, xAxisYPos + 1, 1, graphEndY - (xAxisYPos + 1), self.symbols.SYM_full_block)
                            else
                                if datumYPos > graphStartY then
                                    gpu.fill(datumXPos, xAxisYPos + 1, 1, datumYPos - (xAxisYPos + 1), self.symbols.SYM_full_block)
                                    datumY = datumY + (yScale * (datumYPos - (xAxisYPos + 1)))
                                end
                                -- we need to draw the block as inverted, so we invert the colors since actual inverted block is not available
                                gpu.setBackground(objects[ID].fgColor)
                                gpu.setForeground(self.colors.COLOR_general_bg)
                                gpu.set(datumXPos, datumYPos-1, self:chooseEndSymbolForBar(datumY, yScale))
                                gpu.setBackground(self.colors.COLOR_general_bg)
                                gpu.setForeground(objects[ID].fgColor)
                            end
                        end
                    else
                        if datumY > 0 then
                            gpu.set(datumXPos, xAxisYPos, self.symbols.SYM_upper_block)
                            datumY = datumY - (yScale * 0.5)
                            if datumY > 0 then
                                local datumYPos = math.floor(self.map(kwlib, datumY, yLims, {graphEndY, graphStartY})) + 1
                                if datumYPos < graphStartY then
                                    gpu.fill(datumXPos, xAxisYPos - 1, 1, (xAxisYPos - 1) - graphStartY, self.symbols.SYM_full_block)
                                else
                                    if datumYPos < graphEndY then
                                        gpu.fill(datumXPos, xAxisYPos - 1, 1, (xAxisYPos - 1) - datumYPos, self.symbols.SYM_full_block)
                                        datumY = datumY - (yScale * ((xAxisYPos - 1) - datumYPos))
                                    end
                                    gpu.set(datumXPos, datumYPos-1, self:chooseEndSymbolForBar(datumY, yScale))
                                end
                            end
                        elseif datumY < 0 then
                            gpu.set(datumXPos, xAxisYPos, self.symbols.SYM_lower_block)
                            datumY = datumY + (yScale * 0.5)
                            if datumY < yLims[2] then
                                local datumYPos = math.floor(self.map(kwlib, datumY, yLims, {graphEndY, graphStartY}))
                                if datumYPos > graphEndY then
                                    gpu.fill(datumXPos, xAxisYPos + 1, 1, graphEndY - (xAxisYPos + 1), self.symbols.SYM_full_block)
                                else
                                    if datumYPos > graphStartY then
                                        gpu.fill(datumXPos, xAxisYPos + 1, 1, datumYPos - (xAxisYPos + 1), self.symbols.SYM_full_block)
                                        datumY = datumY + (yScale * (datumYPos - (xAxisYPos + 1)))
                                    end
                                    -- we need to draw the block as inverted, so we invert the colors since actual inverted block is not available
                                    gpu.setBackground(objects[ID].fgColor)
                                    gpu.setForeground(self.colors.COLOR_general_bg)
                                    gpu.set(datumXPos, datumYPos-1, self:chooseEndSymbolForBar(datumY, yScale))
                                    gpu.setBackground(self.colors.COLOR_general_bg)
                                    gpu.setForeground(objects[ID].fgColor)
                                end
                            end
                        end
                    end
                end
            end
        end
        -- and finally, axis arrows and labels
        gpu.set((x+w)-1, xAxisYPos, self.symbols.SYM_right_arrowhead)
        if xAxisYPos > (y+h)/2 then
            gpu.set((x+w)-1, xAxisYPos + 1, "X")
        else
            gpu.set((x+w)-1, xAxisYPos - 1, "X")
        end
        gpu.set(yAxisXPos, y, self.symbols.SYM_up_arrowhead)
        if yAxisYPos > (x+w)/2 then
            gpu.set(yAxisXPos + 1, y, "Y")
        else
            gpu.set(yAxisXPos - 1, y, "Y")
        end

        objects[ID].redraw = false
        return true
    end
    return false
end

function GUI.drawPixelArt(self, objects, ID)
    if objects[ID].visible == true and objects[ID].redraw == true then
        gpu.setBackground(self.colors.COLOR_general_bg)
        local x = objects[ID].x
        local y = objects[ID].y
        local w = objects[ID].w
        local h = objects[ID].h

        self:clearArea(x, y, w, h)

        for i = 1, w do
            for j = 1, h do
                gpu.setForeground(objects[ID].pixels[i][j].color)
                gpu.set(x+i-1, y+j-1, objects[ID].pixels[i][j].symbol)
            end
        end

        self:drawBorder(x, y, w, h, objects[ID].borderStyle, objects[ID].title)
        
        objects[ID].redraw = false
        return true
    end
    return false
end

function GUI.drawAutoScrollableDisplayList(self, objects, ID)
    if objects[ID].visible == true and objects[ID].updatesOn == true then
        local FGColor, BGColor = self.colors.COLOR_general_fg, self.colors.COLOR_general_bg
        gpu.setForeground(FGColor)
        gpu.setBackground(BGColor)

        local x, y, w, h = self:drawBorderAndGetDimensions(objects, ID)

        self:clearArea(x, y, w, h)

        local rowsPerElement = 3
        if objects[ID].elementBorderStyle == "thick" or objects[ID].elementBorderStyle == "slim" then
            rowsPerElement = 3 
        else 
            rowsPerElement = 1 
        end
        local firstElementIndex = math.floor(objects[ID].yPos/rowsPerElement)
        local elementOffset = math.fmod(objects[ID].yPos, rowsPerElement)

        for i = 1, math.min(math.ceil(h/rowsPerElement)+1, #objects[ID].elements), 1 do
            -- skip elements that would show only the border line
            if rowsPerElement == 1 or not (((y+(3*(i-1))-elementOffset)<=(y-2)) or ((y+(3*(i-1))-elementOffset)>=(h+1))) then
                -- need a separate variable for looping lists
                local elementIndex = firstElementIndex + i
                if elementIndex > #objects[ID].elements then elementIndex = elementIndex - #objects[ID].elements end
                -- set element colors
                FGColor, BGColor = objects[ID].elements[elementIndex].colorFunction(objects[ID].elements[elementIndex].content)
                gpu.setForeground(FGColor)
                gpu.setBackground(BGColor)

                -- draw border around the element
                self:drawBorder(x, y + (rowsPerElement*(i-1)) - elementOffset, w, rowsPerElement, objects[ID].elements[elementIndex].borderStyle)
                -- draw element text
                gpu.set(x + (1 - rowsPerElement%3), y + (rowsPerElement*(i-1)) - elementOffset + (1 - rowsPerElement%3), objects[ID].elements[elementIndex].content)
            end
        end

        -- redraw the border, since we might have written over it when drawing the edge cases
        local FGColor, BGColor = self.colors.COLOR_general_fg, self.colors.COLOR_general_bg
        gpu.setForeground(FGColor)
        gpu.setBackground(BGColor)
        self:drawBorderAndGetDimensions(objects, ID)
        return true
    end
    return false
end

function GUI.drawSymbolArray(self, objects, ID)
    if objects[ID].visible == false then
        return false
    end

    local FGColor, BGColor = self.colors.COLOR_general_fg, self.colors.COLOR_general_bg
    gpu.setForeground(FGColor)
    gpu.setBackground(BGColor)

    local x, y, w, h = self:drawBorderAndGetDimensions(objects, ID)

    self:clearArea(x, y, w, h)

    -- concatenate each row together and then write to the screen to save gpu time
    for i, row in ipairs(objects[ID].array) do
        local line = ""
        for j, symbol in ipairs(objects[ID].array[i]) do
            line = line .. objects[ID].array[i][j]
        end
        gpu.set(x, y + i - 1, line)
    end

    return true
end

function GUI.redraw(self)
    self:clearScreen()

    for i = 1, #self.objects do
        if self.objects[i].type == "SelectList" then
            self:drawSelectList(self.objects, i)
            goto continue
        end
        if self.objects[i].type == "OneLineTextField" then
            self:drawOneLineTextField(self.objects, i)
            goto continue
        end
        if self.objects[i].type == "Button" then
            self:drawButton(self.objects, i)
            goto continue
        end
        if self.objects[i].type == "Label" then
            self:drawLabel(self.objects, i)
            goto continue
        end
        if self.objects[i].type == "BarGraph" then
            self:drawBarGraph(self.objects, i)
            goto continue
        end
        if self.objects[i].type == "PixelArt" then
            self:drawPixelArt(self.objects, i)
            goto continue
        end
        if self.objects[i].type == "AutoScrollableDisplayList" then
            self:drawAutoScrollableDisplayList(self.objects, i)
            goto continue
        end
        if self.objects[i].type == "SymbolArray" then
            self:drawSymbolArray(self.objects, i)
            goto continue
        end
        if string.sub(self.objects[i].type, 1, 6) == "Custom" then
            self.objects[i].onDraw(self, self.objects, i)
            goto continue
        end
        ::continue::
    end

    return true
end

function GUI.createSelectList(self, listID, x, y, w, h, borderStyle)
    local newSelectList = {}
    newSelectList.type = "SelectList"
    newSelectList.visible = true
    newSelectList.ID = listID
    newSelectList.x = x
    newSelectList.y = y
    newSelectList.w = w
    newSelectList.h = h
    newSelectList.borderStyle = borderStyle

    newSelectList.upText   =  "/\\/\\ SCROLL UP /\\ /\\"
    newSelectList.upScrollActive = false
    newSelectList.downText = "\\/\\/ SCROLL DOWN \\/\\/"
    newSelectList.downScrollActive = false
    newSelectList.scrollable = false
    newSelectList.position = 1
    newSelectList.items = {}
    newSelectList.selectedItem = nil

    return newSelectList
end

function GUI.addItemToSelectList(self, listID, itemID, itemContent, itemCallback, itemCallbackArguments)
    if itemID == nil or itemCallback == nil then
        return false
    end
    for i = 1, #self.objects do
        if self.objects[i].type == "SelectList" then
            if self.objects[i].ID == listID then
                local newItem = {}
                newItem.ID = itemID
                newItem.content = itemContent
                newItem.callback = itemCallback
                newItem.callbackArguments = itemCallbackArguments
                table.insert(self.objects[i].items, newItem)

                if self.objects[i].borderStyle == "slim" or self.objects[i].borderStyle == "thick" then
                    if #self.objects[i].items > (self.objects[i].h - 2) then
                        self.objects[i].scrollable = true
                        self.objects[i].downScrollActive = true
                    end
                elseif #self.objects[i].items > self.objects[i].h then
                    self.objects[i].scrollable = true
                    self.objects[i].downScrollActive = true
                end

                return true
            end
        end
    end
    return false
end

function GUI.changeItemInSelectList(self, listID, itemID, newItemContent, newCallback, newCallbackArguments)
    for i = 1, #self.objects do
        if self.objects[i].type == "SelectList" then
            if self.objects[i].ID == listID then
                for j = 1, #self.objects[i].items, 1 do
                    if self.objects[i].items[j].ID == itemID then
                        self.objects[i].items[j].content = newItemContent
                        if type(newCallback) == "function" then
                            self.objects[i].items[j].callback = newCallback
                        end
                        if newCallbackArguments ~= nil then
                            self.objects[i].items[j].callbackArguments = newCallbackArguments
                        end
                        return true
                    end
                end
            end
        end
    end
    return false
end

function GUI.createOneLineTextField(self, textID, defaultText, x, y, w, h)
    local newOneLineTextField = {}
    newOneLineTextField.type = "OneLineTextField"
    newOneLineTextField.visible = true
    newOneLineTextField.ID = textID
    newOneLineTextField.x = x
    newOneLineTextField.y = y
    newOneLineTextField.w = w
    newOneLineTextField.h = h
    newOneLineTextField.defaultText = defaultText

    newOneLineTextField.value = defaultText
    newOneLineTextField.focused = false
    newOneLineTextField.position = string.len(defaultText) + 1
    newOneLineTextField.caret_symbol = self.symbols.SYM_caret
    newOneLineTextField.onClick = function(...) return true end

    return newOneLineTextField
end

function GUI.getTextFromOneLineTextField(self, objects, textID)
    for i = #objects, 1, -1 do
        if objects[i].type == "OneLineTextField" then
            if objects[i].ID == textID then
                return objects[i].value
            end
        end
    end
    return nil
end

function GUI.getObjectSize(self, objects, ID)
    for i = #objects, 1, -1 do
        if objects[i].ID == ID then
            if objects[i].w and objects[i].h then
                local size = {}
                size.w = objects[i].w
                size.h = objects[i].h
                return size
            end
        end
    end
    return nil
end

function GUI.setObjectSize(self, objects, ID, size)
    for i = #objects, 1, -1 do
        if objects[i].ID == ID then
            if objects[i].w and objects[i].h then
                objects[i].w = size.w
                objects[i].h = size.h
                return true
            end
        end
    end
    return false
end

function GUI.onButtonClick(self, objects, ID, ...)
    if objects[ID].active == true then
        objects[ID].pressed = true
        objects[ID].callback(...)
        return true
    end
    return false
end

function GUI.createButton(self, buttonID, text, callback, x, y, w, h, borderStyle)
    local newButton = {}
    newButton.type = "Button"
    newButton.visible = true
    newButton.ID = buttonID
    newButton.value = text
    newButton.callback = callback
    newButton.x = x
    newButton.y = y
    newButton.w = w
    newButton.h = h
    newButton.borderStyle = borderStyle

    newButton.active = true
    newButton.pressed = false
    newButton.fgcolor = self.colors.COLOR_button_fg
    newButton.inactivebgcolor = self.colors.COLOR_button_inactive_bg
    newButton.activegbcolor = self.colors.COLOR_button_active_bg
    newButton.pressedbgcolor = self.colors.COLOR_button_pressed_bg
    newButton.onClick = self.onButtonClick

    return newButton
end

function GUI.createLabel(self, labelID, text, x, y, w, h, borderStyle)
    local newLabel = {}
    newLabel.type = "Label"
    newLabel.visible = true
    newLabel.ID = labelID
    newLabel.value = text
    newLabel.x = x
    newLabel.y = y
    newLabel.w = w
    newLabel.h = h
    newLabel.borderStyle = borderStyle

    return newLabel
end

function GUI.createBarGraph(self, barGraphID, title, xLabel, yLabel, x, y, w, h, borderStyle, dataColor, storageSize)
    local newBarGraph = {}
    newBarGraph.type = "BarGraph"
    newBarGraph.visible = true
    newBarGraph.ID = barGraphID
    newBarGraph.x = x
    newBarGraph.y = y
    newBarGraph.w = w
    newBarGraph.h = h
    newBarGraph.borderStyle = borderStyle

    newBarGraph.storageSize = storageSize
    newBarGraph.Data = kwlib.general.createCircularBuffer(kwlib, storageSize)
    for i = 1, storageSize do
        newBarGraph.Data.addDatum({i, 0})
    end
    newBarGraph.xLabel = xLabel
    newBarGraph.yLabel = yLabel
    newBarGraph.xLims = {-1, 1}
    newBarGraph.yLims = {0, 1}
    newBarGraph.autoXLims = true
    newBarGraph.autoYLims = true
    newBarGraph.drawAxes = true
    newBarGraph.title = title
    newBarGraph.showTitle = true
    newBarGraph.legend = {}
    newBarGraph.showLegend = false
    newBarGraph.fgColor = dataColor
    newBarGraph.redraw = true

    return newBarGraph
end

function GUI.addDatumToBarGraph(self, barGraphID, datum)
    if barGraphID == nil or datum == nil then
        return false
    end
    for i = 1, #self.objects do
        if self.objects[i].type == "BarGraph" then
            if self.objects[i].ID == barGraphID then
                self.objects[i].Data.addDatum(datum)
                return true
            end
        end
    end
    return false
end

function GUI.createPixelArt(self, pixelArtID, x, y, w, h, borderStyle, title)
    local newPixelArt = {}
    newPixelArt.type = "PixelArt"
    newPixelArt.visible = true
    newPixelArt.ID = pixelArtID
    newPixelArt.x = x
    newPixelArt.y = y
    newPixelArt.w = w
    newPixelArt.h = h
    newPixelArt.borderStyle = borderStyle
    newPixelArt.title = title
    newPixelArt.redraw = true

    newPixelArt.pixels = {}
    for i = 1, w do
        pixels[i] = {}
        for j = 1, h do
            pixels[i][j] = {}
            pixels[i][j].color = self.colors.COLOR_general_bg
            pixels[i][j].symbol = " "
        end
    end

    return newPixelArt
end

function GUI.setPixelInPixelArt(self, pixelArtID, pixelX, pixelY, pixelColor)
    if type(pixelArtID) ~= number or type(pixelColor) ~= number then
        return false
    end
    for i = 1, #self.objects do
        if self.objects[i].type == "PixelArt" then
            if self.objects[i].ID == pixelArtID then
                self.objects[i].pixels[pixelX][pixelY].color = pixelColor
                if pixelColor == self.colors.COLOR_general_bg then
                    self.objects[i].pixels[pixelX][pixelY].symbol = " "
                else
                    self.objects[i].pixels[pixelX][pixelY].symbol = self.symbols.SYM_full_block
                end
                return true
            end
        end
    end
    return false
end

function GUI.createAutoScrollableDisplayList(self, listID, x, y, w, h, borderStyle, elementBorderStyle, looping, rowsPerUpdate, ticksPerUpdate)
    local newAutoScrollableDisplayList  = {}
    newAutoScrollableDisplayList.type = "AutoScrollableDisplayList"
    newAutoScrollableDisplayList.visible = true
    newAutoScrollableDisplayList.ID = listID
    newAutoScrollableDisplayList.x = x
    newAutoScrollableDisplayList.y = y
    newAutoScrollableDisplayList.w = w
    newAutoScrollableDisplayList.h = h
    newAutoScrollableDisplayList.borderStyle = borderStyle

    newAutoScrollableDisplayList.elementBorderStyle = elementBorderStyle
    newAutoScrollableDisplayList.elements           = {}
    newAutoScrollableDisplayList.yPos               = 0
    newAutoScrollableDisplayList.looping            = looping
    newAutoScrollableDisplayList.rowsPerUpdate      = rowsPerUpdate
    newAutoScrollableDisplayList.updatesOn          = true
    newAutoScrollableDisplayList.totalHeight        = 0
    newAutoScrollableDisplayList.scrollingDirection = 1
    newAutoScrollableDisplayList.ticksPerUpdate     = ticksPerUpdate
    newAutoScrollableDisplayList.ticksSinceUpdate   = 0

    newAutoScrollableDisplayList.onTick = function(objects, ID)
        if objects[ID].updatesOn and objects[ID].totalHeight > 0 and objects[ID].totalHeight > (objects[ID].h-2) then
            objects[ID].ticksSinceUpdate = objects[ID].ticksSinceUpdate + 1
            if objects[ID].ticksSinceUpdate >= objects[ID].ticksPerUpdate then
                objects[ID].yPos = objects[ID].yPos + objects[ID].scrollingDirection * objects[ID].rowsPerUpdate
                objects[ID].ticksSinceUpdate = 0
            end
            if objects[ID].looping == true then
                if objects[ID].yPos >= objects[ID].totalHeight  then objects[ID].yPos = objects[ID].yPos - objects[ID].totalHeight end
                if objects[ID].yPos < 0                         then objects[ID].yPos = objects[ID].yPos + objects[ID].totalHeight end
            else
                if objects[ID].yPos >= objects[ID].totalHeight - objects[ID].h then 
                    objects[ID].yPos = (objects[ID].totalHeight - objects[ID].h) - 1
                    objects[ID].scrollingDirection = -objects[ID].scrollingDirection
                elseif objects[ID].yPos < 0 then 
                    objects[ID].yPos = 0
                    objects[ID].scrollingDirection = -objects[ID].scrollingDirection
                end
            end
        end
    end

    return newAutoScrollableDisplayList
end

-- the color function should take the content string as an argument and return two 0xRRGGBB values of color (background and foreground)
function GUI.addItemToAutoScrollableDisplayList(self, listID, itemID, itemContents, itemColorFunction)
    for i = 1, #self.objects do
        if self.objects[i].type == "AutoScrollableDisplayList" then
            if self.objects[i].ID == listID then
                table.insert(self.objects[i].elements, {
                    ID              = itemID,
                    content         = itemContents,
                    borderStyle     = self.objects[i].elementBorderStyle,
                    colorFunction   = itemColorFunction
                })
                if self.objects[i].elementBorderStyle == 'thick' or self.objects[i].elementBorderStyle == 'slim' then
                    self.objects[i].totalHeight = self.objects[i].totalHeight + 3 
                else 
                    self.objects[i].totalHeight = self.objects[i].totalHeight + 1
                end
                return true
            end
        end
    end
    return false
end

function GUI.changeItemContentsInAutoScrollableDisplayList(self, listID, itemID, newItemContents)
    for i = 1, #self.objects do
        if self.objects[i].type == "AutoScrollableDisplayList" then
            if self.objects[i].ID == listID then
                for j = 1, self.objects[i].elements do
                    if self.objects[i].elements[j].ID == itemID then self.objects[i].elements[j].content = newItemContents end
                    return true
                end
            end
        end
    end
    return false
end

function GUI.createInfoBox(self, infoBoxID, borderStyle, title, text)
    local newInfoBox = {}
    newInfoBox.type = "InfoBox"
    newInfoBox.visible = true
    newInfoBox.ID = infoBoxID

    -- figure out the space we need
    -- first, width, set to 2/3 of the screen width, the text length or minimum width needed for an OK button, whichever is smaller
    newInfoBox.w = math.min(math.floor(self.width * (2/3)), text:len() + ((borderStyle=="slim" or borderStyle=="thick") and 2 or 0), 4 + ((borderStyle=="slim" or borderStyle=="thick") and 2 or 0))
    -- then we split the string into smaller strings that fit the width
    newInfoBox.value = kwlib.strings.splitStringIntoLines(kwlib, text, w - ((borderStyle=="slim" or borderStyle=="thick") and 2 or 0))
    -- and set height depending on how many strings we end up with + height needed for the OK button
    newInfoBox.h = ((borderStyle=="slim" or borderStyle=="thick") and 2 or 0) + kwlib.tables.countEntries(kwlib, newInfoBox.value) + 3
    -- set x position to center the box
    newInfoBox.x = math.floor((self.WIDTH - newInfoBox.w)/2)
    -- set y position to center the box
    newInfoBox.y = math.floor((self.HEIGHT - newInfoBox.h)/2)
    newInfoBox.borderStyle = borderStyle
    newInfoBox.title = title
    newInfoBox.content = {}

    function newInfoBox.ack(infoBoxContent, buttonID, gui, objects, ID)
        return gui:removeObject("InfoBox", ID)
    end

    local tempObject = self.createButton(infoBoxID .. "ACK", "OK", newInfoBox.ack, math.floor(newInfoBox.x + (newInfoBox.w / 2) - 2), newInfoBox.y + newInfoBox.h - 3 - ((borderStyle=="slim" or borderStyle=="thick") and 1 or 0), 4, 3, "slim")
    table.insert(newInfoBox.content, tempObject)

    return newInfoBox
end

function GUI.createSymbolArray(self, symbolArrayID, xPos, yPos, width, height)
    local newSymbolArray = {}

    newSymbolArray.type = "SymbolArray"
    newSymbolArray.visible = true
    newSymbolArray.ID = symbolArrayID
    newSymbolArray.x = xPos
    newSymbolArray.y = yPos
    newSymbolArray.w = width
    newSymbolArray.h = height
    newSymbolArray.borderStyle = "none"
    newSymbolArray.array = {}
    for i=1, height, 1 do
        newSymbolArray.array[i] = {}
        for j=1, width, 1 do
            newSymbolArray.array[i][j] = " "
        end
    end
    
    return newSymbolArray
end

function GUI.setSymbolInSymbolArray(self, objects, symbolArrayID, xPos, yPos, symbol)
    for i=#objects, 1, -1 do
        if objects[i].type == "SymbolArray" and objects[i].ID == symbolArrayID then
            if type(objects[i].array[yPos]) == "table" and type(objects[i].array[yPos][xPos]) == "string" then
                objects[i].array[yPos][xPos] = symbol
                return true
            end
        end
    end
    return false
end

------------------------------------------------------------------------------------------
-- layouts
function GUI.createVerticalLayout(self, layoutID, x, y, w, h, borderStyle, numRows, rowHeightTable, hAlign, vAlign, fitObjectsToSize, bordersBetweenRows)
    local newVerticalLayout = {}
    newVerticalLayout.type = "verticalLayout"
    newVerticalLayout.visible = true
    newVerticalLayout.ID = layoutID
    newVerticalLayout.x = x
    newVerticalLayout.y = y
    newVerticalLayout.w = w
    newVerticalLayout.h = h
    newVerticalLayout.borderStyle = borderStyle

    newVerticalLayout.rows = {}
    local rowY = y
    if borderStyle == "thick" or borderStyle == "slim" then rowY = y+1 end
    for i = 1, numRows, 1 do
        newVerticalLayout.rows[i] = {}
        newVerticalLayout.rows[i].y = rowY
        rowY = rowY + rowHeightTable[i]
        newVerticalLayout.rows[i].h = rowHeightTable[i]
        if borderStyle == "thick" or borderStyle == "slim" then
            newVerticalLayout.rows[i].x = x + 1
            newVerticalLayout.rows[i].w = w - 2
        else
            newVerticalLayout.rows[i].x = x
            newVerticalLayout.rows[i].w = w
        end
        if bordersBetweenRows then
            newVerticalLayout.rows[i].h = newVerticalLayout.rows[i].h - 1
        end
        newVerticalLayout.rows[i].content = {}
    end
    newVerticalLayout.hAlign = hAlign
    newVerticalLayout.vAlign = vAlign
    newVerticalLayout.fitObjectsToSize      = fitObjectsToSize
    newVerticalLayout.bordersBetweenRows    = bordersBetweenRows

    return newVerticalLayout
end

------------------------------------------------------------------------------------------

function GUI.addObject(self, objectType, ...)

    if type(objectType) == "table" and objectType.type ~= nil then
        table.insert(self.objects, objectType)
        return true
    end

    if objectType == "SelectList" then
        table.insert(self.objects, self:createSelectList(...))
        return true
    end
    if objectType == "OneLineTextField" then
        table.insert(self.objects, self:createOneLineTextField(...))
        return true
    end
    if objectType == "Button" then
        table.insert(self.objects, self:createButton(...))
        return true
    end
    if objectType == "Label" then
        table.insert(self.objects, self:createLabel(...))
        return true
    end
    if objectType == "BarGraph" then
        table.insert(self.objects, self:createBarGraph(...))
        return true
    end
    if objectType == "PixelArt" then
        table.insert(self.objects, self:createPixelArt(...))
        return true
    end
    if objectType == "AutoScrollableDisplayList" then
        table.insert(self.objects, self:createAutoScrollableDisplayList(...))
        return true
    end
    if objectType == "InfoBox" then
        table.insert(self.objects, self:createInfoBox(...))
        return true
    end
    if objectType == "SymbolArray" then
        table.insert(self.objects, self:createSymbolArray(...))
        return true
    end
    if string.sub(objectType, 1, 6) == "Custom" then
        table.insert(self.objects, ...)
        return true
    end

    return false
end

function GUI.popObject(self)
    if self.objects[#self.objects].onDelete then self.objects[#self.objects].onDelete(self, self.objects[#self.objects]) end
    table.remove(self.objects)
    return true
end

function GUI.removeSelectList(self, listID)
    for i=#self.objects, 1, -1 do
        if self.objects[i].type == "SelectList" then
            if self.objects[i].ID == listID then
                if self.objects[i].onDelete then self.objects[i].onDelete(self, self.objects[i]) end
                table.remove(self.objects, i)
                return true
            end
        end
    end
    return false
end

function GUI.removeFromSelectList(self, listID, itemID)
    for i=#self.objects, 1, -1 do
        if self.objects[i].type == "SelectList" then
            if self.objects[i].ID == listID then
                for j=#self.objects[i].items, 1, -1 do
                    if self.objects[i].items[j].ID == itemID then
                        table.remove(self.objects[i].items, j)
                        if j == self.objects[i].selectedItem then
                            self.objects[i].selectedItem = nil
                        end
                        if self.objects[i].borderStyle == "slim" or self.objects[i].borderStyle == "thick" then
                            if #self.objects[i].items <= (self.objects[i].h - 2) then
                                self.objects[i].scrollable = false
                                self.objects[i].downScrollActive = false
                                self.objects[i].upScrollActive = false
                                self.objects[i].position = 1
                            end
                        elseif #self.objects[i].items <= self.objects[i].h then
                            self.objects[i].scrollable = false
                            self.objects[i].downScrollActive = false
                            self.objects[i].upScrollActive = false
                            self.objects[i].position = 1
                        end
                        return true
                    end
                end
            end
        end
    end
    return false
end

function GUI.popFromSelectList(self, listID)
    for i=#self.objects, 1, -1 do
        if self.objects[i].type == "SelectList" then
            if self.objects[i].ID == listID then
                table.remove(self.objects[i].items)
                if #self.objects[i].items + 1 == self.objects[i].selected_item then
                    self.objects[i].selected_item = nil
                end
                if self.objects[i].borderStyle == "slim" or self.objects[i].borderStyle == "thick" then
                    if #self.objects[i].items <= (self.objects[i].h - 2) then
                        self.objects[i].scrollable = false
                        self.objects[i].downScrollActive = false
                        self.objects[i].upScrollActive = false
                        self.objects[i].position = 1
                    end
                elseif #self.objects[i].items <= self.objects[i].h then
                    self.objects[i].scrollable = false
                    self.objects[i].downScrollActive = false
                    self.objects[i].upScrollActive = false
                    self.objects[i].position = 1
                end
                return true
            end
        end
    end
    return false
end

function GUI.removeOneLineTextField(self, textID)
    for i=#self.objects, 1, -1 do
        if self.objects[i].type == "OneLineTextField" then
            if self.objects[i].ID == textID then
                if self.objects[i].onDelete then self.objects[i].onDelete(self, self.objects[i]) end
                table.remove(self.objects, i)
                return true
            end
        end
    end
    return false
end

function GUI.removeButton(self, buttonID)
    for i=#self.objects, 1, -1 do
        if self.objects[i].type == "Button" then
            if self.objects[i].ID == buttonID then
                if self.objects[i].onDelete then self.objects[i].onDelete(self, self.objects[i]) end
                table.remove(self.objects, i)
                return true
            end
        end
    end
    return false
end

function GUI.removeCustomObject(self, objectType, objectID)
    for i=#self.objects, 1, -1 do
        if self.objects[i].type == objectType then
            if self.objects[i].ID == objectID then
                if self.objects[i].onDelete then self.objects[i].onDelete(self, self.objects[i]) end
                table.remove(self.objects, i)
                return true
            end
        end
    end
    return false
end

function GUI.removeLabel(self, labelID)
    for i=#self.objects, 1, -1 do
        if self.objects[i].type == "Label" then
            if self.objects[i].ID == labelID then
                if self.objects[i].onDelete then self.objects[i].onDelete(self, self.objects[i]) end
                table.remove(self.objects, i)
                return true
            end
        end
    end
    return false
end

function GUI.removeBarGraph(self, barGraphID)
    for i=#self.objects, 1, -1 do
        if self.objects[i].type == "BarGraph" then
            if self.objects[i].ID == barGraphID then
                if self.objects[i].onDelete then self.objects[i].onDelete(self, self.objects[i]) end
                table.remove(self.objects, i)
                return true
            end
        end
    end
    return false
end

function GUI.removePixelArt(self, pixelArtID)
    for i=#self.objects, 1, -1 do
        if self.objects[i].type == "PixelArt" then
            if self.objects[i].ID == pixelArtID then
                if self.objects[i].onDelete then self.objects[i].onDelete(self, self.objects[i]) end
                table.remove(self.objects, i)
                return true
            end
        end
    end
    return false
end

function GUI.removeAutoScrollableDisplayList(self, autoScrollableDisplayListID)
    for i=#self.objects, 1, -1 do
        if self.objects[i].type == "AutoScrollableDisplayList" then
            if self.objects[i].ID == autoScrollableDisplayListID then
                if self.objects[i].onDelete then self.objects[i].onDelete(self, self.objects[i]) end
                table.remove(self.objects, i)
                return true
            end
        end
    end
    return false
end

function GUI.removeFromAutoScrollableDisplayList(self, autoScrollableDisplayListID, itemID)
    for i=#self.objects, 1, -1 do
        if self.objects[i].type == "AutoScrollableDisplayList" then
            if self.objects[i].ID == autoScrollableDisplayListID then
                for j=#self.objects[i].objects, 1, -1 do
                    if self.objects[i].objects[j].ID == itemID then
                        if self.objects[i].objects[j].onDelete then self.objects[i].objects[j].onDelete(self, self.objects[i].objects[j]) end
                        table.remove(self.objects[i].objects, j)
                        if self.objects[i].elementBorderStyle == 'thick' or self.objects[i].elementBorderStyle == 'slim' then
                            self.objects[i].totalHeight = self.objects[i].totalHeight - 3 
                        else 
                            self.objects[i].totalHeight = self.objects[i].totalHeight - 1 
                        end
                        return true
                    end
                end
            end
        end
    end
    return false
end

function GUI.removeInfoBox(self, infoBoxID)
    for i=#self.objects, 1, -1 do
        if self.objects[i].type == "InfoBox" then
            if self.objects[i].ID == infoBoxID then
                if self.objects[i].onDelete then self.objects[i].onDelete(self, self.objects[i]) end
                table.remove(self.objects, i)
                return true
            end
        end
    end
    return false
end

function GUI.removeSymbolArray(self, symbolArrayID)
    for i=#self.objects, 1, -1 do
        if self.objects[i].type == "SymbolArray" then
            if self.objects[i].ID == symbolArrayID then
                if self.objects[i].onDelete then self.objects[i].onDelete(self, self.objects[i]) end
                table.remove(self.objects, i)
                return true
            end
        end
    end
    return false
end

function GUI.removeObject(self, objectType, ...)

    if objectType == "SelectList" then
        return self:removeSelectList(...)
    end
    if objectType == "SelectListItem" then
        return self:removeFromSelectList(...)
    end
    if objectType == "OneLineTextField" then
        return self:removeOneLineTextField(...)
    end
    if objectType == "Button" then
        return self:removeButton(...)
    end
    if objectType == "Label" then
        return self:removeLabel(...)
    end
    if objectType == "BarGraph" then
        return self:removeBarGraph(...)
    end
    if objectType == "PixelArt" then
        return self:removePixelArt(...)
    end
    if objectType == "AutoScrollableDisplayList" then
        return self:removeAutoScrollableDisplayList(...)
    end
    if objectType == "InfoBox" then
        return self:removeInfoBox(...)
    end
    if objectType == "SymbolArray" then
        return self:removeSymbolArray(...)
    end
    if string.sub(objectType, 1, 6) == "Custom" then
        return self:removeCustomObject(objectType, ...)
    end

    return false
end

function GUI.selectFromList(self, objects, ID, mouseY)
    local mouseListPos = mouseY - objects[ID].y
    if mouseListPos > 0 and mouseListPos < objects[ID].h then
        if objects[ID].scrollable then

            if ((objects[ID].borderStyle == "slim" or objects[ID].borderStyle == "thick") and mouseListPos == 1)
            or (not (objects[ID].borderStyle == "slim" or objects[ID].borderStyle == "thick") and mouseListPos == 0) then
                if objects[ID].upScrollActive == true then
                    objects[ID].position = objects[ID].position - 1
                    return true
                else
                    return false
                end
            end

            if ((objects[ID].borderStyle == "slim" or objects[ID].borderStyle == "thick") and mouseListPos == (objects[ID].h - 2))
            or (not (objects[ID].borderStyle == "slim" or objects[ID].borderStyle == "thick") and mouseListPos == (objects[ID].h - 1)) then
                if objects[ID].downScrollActive == true then
                    objects[ID].position = objects[ID].position + 1
                    return true
                else
                    return false
                end
            end

            local selected_item = objects[ID].position + (mouseListPos - 1)
            if objects[ID].items[mouseListPos].callback and objects[ID].items[selected_item]:callback(objects[ID].items[selected_item].callbackArguments) then
                objects[ID].selected_item = selected_item
                return true
            end
        elseif mouseListPos <= #objects[ID].items then
            if objects[ID].items[mouseListPos].callback and objects[ID].items[mouseListPos]:callback(objects[ID].items[mouseListPos].callbackArguments) then
                objects[ID].selected_item = mouseListPos
                return true
            end
        end
    end
    
    return false
end

function GUI.focusOnOneLineTextField(self, objects, ID)
    self.focusedTextInputID = ID
    objects[ID].focused = true
    return true
end

function GUI.pressButton(self, objects, ID, ...)
    if objects[ID].type == "Button" then
        if objects[ID].active == true then
            return objects[ID].onClick(self, objects, ID, ...)
        end
    end
    return false
end

function GUI.clickOnInfoBox(self, objects, ID, ...)
    local args = {...}
    local xPos = args[2]
    local yPos = args[3]

    if self:checkIfWithinObjectBoundary(xPos, yPos, objects[ID].content[1]) then
        return self:pressButton(objects[ID], ID .. "ACK", self, objects, ID)
    end
    return false
end

function GUI.clickOnCustom(self, objects, ID, ...)

    if objects[ID].onClick then
        self.focusedCustomObjectID = ID
        if objects[ID].focused then
            if objects[ID] == false then
                objects[ID].focused = true
            end
        else
            objects[ID].focused = true
        end
        return objects[ID].onClick(self, objects, ID, ...)
    end

    return false
end

function GUI.writeInOneLineTextField(self, objects, ID, ...)
    local args = {...}
    local char = args[2]
    local key  = args[3]

    if key == keyboard.keys.back then
        if objects[ID].position > 1 then
            if objects[ID].position == 2 then
                objects[ID].value = string.sub(objects[ID].value, 2, string.len(objects[ID].value))
            elseif objects[ID].position <= string.len(objects[ID].value) then
                objects[ID].value = string.sub(objects[ID].value, 1, objects[ID].position-2) .. string.sub(objects[ID].value, objects[ID].position, string.len(objects[ID].value))
            else
                objects[ID].value = string.sub(objects[ID].value, 1, objects[ID].position-2)
            end
            objects[ID].position = objects[ID].position - 1
        end
        return true
    end
    if key == keyboard.keys.delete then
        if objects[ID].position < string.len(objects[ID].value)+1 then
            if objects[ID].position == 1 then
                objects[ID].value = string.sub(objects[ID].value, 2, string.len(objects[ID].value))
            elseif objects[ID].position < string.len(objects[ID].value) then
                objects[ID].value = string.sub(objects[ID].value, 1, objects[ID].position-1) .. string.sub(objects[ID].value, objects[ID].position+1, string.len(objects[ID].value))
            else
                objects[ID].value = string.sub(objects[ID].value, 1, objects[ID].position-1)
            end
        end
        return true
    end
    if key == keyboard.keys.left then
        if objects[ID].position > 1 then
            objects[ID].position = objects[ID].position - 1
        end
        return true
    end
    if key == keyboard.keys.right then
        if objects[ID].position < (string.len(objects[ID].value)+1) then
            objects[ID].position = objects[ID].position + 1
        end
        return true
    end
    if key == keyboard.keys.home then
        objects[ID].position = 1
        return true
    end
    if key == keyboard.keys["end"] then
        objects[ID].position = (string.len(objects[ID].value)+1)
        return true
    end

    if string.char(char) == "-" then
        if objects[ID].position == 1 then
            objects[ID].value = "-" .. objects[ID].value
        elseif objects[ID].position == string.len(objects[ID].value)+1 then
            objects[ID].value = objects[ID].value .. "-"
        else
            objects[ID].value = string.sub(objects[ID].value, 1, objects[ID].position-1) .. "-" .. string.sub(objects[ID].value, objects[ID].position, string.len(objects[ID].value))
        end
        objects[ID].position = objects[ID].position + 1
        return true
    end

    for i = string.byte("0"),string.byte("9") do
        if char == i then
            if objects[ID].position == 1 then
                objects[ID].value = string.char(char) .. objects[ID].value
            elseif objects[ID].position == string.len(objects[ID].value)+1 then
                objects[ID].value = objects[ID].value .. string.char(char)
            else
                objects[ID].value = string.sub(objects[ID].value, 1, objects[ID].position-1) .. string.char(char) .. string.sub(objects[ID].value, objects[ID].position, string.len(objects[ID].value))
            end
            objects[ID].position = objects[ID].position + 1
            return true
        end
    end

    for i = string.byte("a"),string.byte("z") do
        if char == i then
            if objects[ID].position == 1 then
                objects[ID].value = string.char(char) .. objects[ID].value
            elseif objects[ID].position == string.len(objects[ID].value)+1 then
                objects[ID].value = objects[ID].value .. string.char(char)
            else
                objects[ID].value = string.sub(objects[ID].value, 1, objects[ID].position-1) .. string.char(char) .. string.sub(objects[ID].value, objects[ID].position, string.len(objects[ID].value))
            end
            objects[ID].position = objects[ID].position + 1
            return true
        end
    end

    for i = string.byte("A"),string.byte("Z") do
        if char == i then
            if objects[ID].position == 1 then
                objects[ID].value = string.char(char) .. objects[ID].value
            elseif objects[ID].position == string.len(objects[ID].value)+1 then
                objects[ID].value = objects[ID].value .. string.char(char)
            else
                objects[ID].value = string.sub(objects[ID].value, 1, objects[ID].position-1) .. string.char(char) .. string.sub(objects[ID].value, objects[ID].position, string.len(objects[ID].value))
            end
            objects[ID].position = objects[ID].position + 1
            return true
        end
    end

    return false
end

function GUI.sendKeyDownToCustomObject(self, objects, ID, ...)
    if objects[ID] then
        if objects[ID].onKeyDown then
            return objects[ID].onKeyDown(self, objects, ID, ...)
        end
    end
    return false
end

-- function to register custom event handlers
-- the callback function should return 'true' if it requires the screen to be redrawn or 'false' if it does not
function GUI.registerEventHandler(self, eventID, callback, handlerID)
    local newEventHandler = {}
    newEventHandler.eventID = eventID
    newEventHandler.callback = callback
    if handlerID ~= nil then
        if self.eventHandlers[handlerID] == nil then
            self.eventHandlers[handlerID] = newEventHandler
        else return false end
    else
        table.insert(self.eventHandlers, newEventHandler)
    end
    return true
end

function GUI.removeEventHandler(self, handlerID)
    self.eventHandlers[handlerID] = nil
    return true
end

function GUI.handleClick(self, ...)
    local args = {...}
    local xPos = args[2]
    local yPos = args[3]

    if self.focusedTextInputID then
        self.objects[self.focusedTextInputID].focused = false
        self.focusedTextInputID = nil
    end

    if self.focusedCustomObjectID then
        if self.objects[self.focusedCustomObjectID] then
            if self.objects[self.focusedCustomObjectID].focused then
                self.objects[self.focusedCustomObjectID].focused = false
            end
        end
        self.focusedCustomObjectID = nil
    end

    for i = #self.objects,1, -1 do
        if self.objects[i].x and self.objects[i].y and self.objects[i].w and self.objects[i].h then
            if self:checkIfWithinObjectBoundary(xPos, yPos, self.objects[i]) then
                self.lastObjectPressed = i
                if self.objects[i].type == "SelectList" then
                    if self:selectFromList(self.objects, i, yPos) == true then
                        return true
                    end
                end
                if self.objects[i].type == "OneLineTextField" then
                    if self:focusOnOneLineTextField(self.objects, i) == true then
                        return true
                    end
                end
                if self.objects[i].type == "Button" then
                    if self:pressButton(self.objects, i, ...) == true then
                        return true
                    end
                end
                if self.objects[i].type == "InfoBox" then
                    if self:clickOnInfoBox(self.objects, i, ...) == true then
                        return true
                    end
                end
                if string.sub(self.objects[i].type, 1, 6) == "Custom" then
                    if self:clickOnCustom(self.objects, i, ...) == true then
                        return true
                    end
                end
            end
        end
    end
    return false
end

function GUI.tickObjects(self)
    while self.running do
        for i = #self.objects, 1, -1 do
            if self.objects[i].onTick ~= nil then
                self.objects[i].onTick(self.objects, i)
            end
        end
        if self.redrawOnTick == true and self.ticksSinceRedraw == self.ticksPerRedraw then
            event.push("redraw")
            self.ticksSinceRedraw = 0
        end
        if self.redrawOnTick == true then self.ticksSinceRedraw = self.ticksSinceRedraw + 1 end
        os.sleep(1.0 / self.tickRate)
    end
end

function GUI.handleEvent(self, eventID, ...)
    if eventID == "redraw" then return true end
    if eventID == "interrupted" then
        self.running = false
        redraw = true
        return redraw
    end

    local args = {...}
    local redraw = false

    if self.lastObjectPressed then
        if self.objects[self.lastObjectPressed] then
            if self.objects[self.lastObjectPressed].pressed then
                self.objects[self.lastObjectPressed].pressed = false
            end
        end
        self.lastObjectPressed = nil
    end

    for handlerID, handler in pairs(self.eventHandlers) do
        if handler.eventID == eventID then
            redraw = handler.callback(eventID, ...) or redraw
        end
    end

    if eventID == "touch" then
        redraw = self:handleClick(...) or redraw
    end

    if eventID == "key_down" then
        if self.focusedTextInputID then
            redraw = self:writeInOneLineTextField(self.objects, self.focusedTextInputID, ...)      or redraw
        end
        if self.focusedCustomObjectID then
            redraw = self:sendKeyDownToCustomObject(self.objects, self.focusedCustomObjectID, ...) or redraw
        end
        if string.char(args[2]) == "q" and keyboard.isControlDown() then
            self.running = false
            redraw = true
        end
    end

    return redraw
end

function GUI.cleanup(self)
    self:clearScreen()
    self.objects = {}
    self.objects[1] = {type = "GUI"}
    self.eventHandlers = {}
    self.eventHandlers[1] = {eventID = "VOID"}
    self.focusedTextInputID = nil
    self.lastObjectPressed = nil
    return true
end

function GUI.run(self)
    self.running = true
    self:redraw()
    self.tickThread = thread.create(self.tickObjects, self)
    while self.running do
        if self:handleEvent(event.pull()) == true then
            self:redraw()
        end
    end
    if self.tickThread ~= nil and self.tickThread:status() == "running" then
        thread.waitForAll(self.tickThread)
    end
    self:cleanup()
    return true
end

function GUI.exit(self)
    self.running = false
end

function GUI.stopTicks(self)
    if self.tickThread ~= nil and thread.status(self.tickThread) == "running" then
        thread.suspend(self.tickThread)
        return true
    end
    return false
end

function GUI.startTicks(self)
    if self.tickThread ~= nil and thread.status(self.tickThread) == "suspended" then
        thread.resume(self.tickThread)
        return true
    end
    return false
end

return GUI