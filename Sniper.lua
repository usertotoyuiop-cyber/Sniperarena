-- ==========================================================
-- NURHUB v1.1 | Delta Executor Compatible | без Drawing API
-- ==========================================================

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local LocalPlayer = Players.LocalPlayer
local Camera = workspace.CurrentCamera

-- ==========================================================
-- 0. ОЧИСТКА ПРИ ПОВТОРНОМ ЗАПУСКЕ + ТРЕКЕР СОЕДИНЕНИЙ
-- ==========================================================
local ENV = (getgenv and getgenv()) or _G
if ENV.NurHubCleanup then pcall(ENV.NurHubCleanup) end

local Conns = {}
local function track(conn)
    table.insert(Conns, conn)
    return conn
end

local function getGuiParent()
    local ok, result = pcall(function()
        return (gethui and gethui()) or game:GetService("CoreGui")
    end)
    if ok and result then return result end
    return LocalPlayer:WaitForChild("PlayerGui")
end

ENV.NurHubCleanup = function()
    for _, c in ipairs(Conns) do pcall(function() c:Disconnect() end) end
    Conns = {}
    pcall(function() RunService:UnbindFromRenderStep("NurHubLoop") end)
    local gp = getGuiParent()
    for _, n in ipairs({"NurHubGui", "NurHubESPGui"}) do
        local g = gp:FindFirstChild(n)
        if g then g:Destroy() end
    end
    -- убираем остатки ESP из персонажей
    for _, p in ipairs(Players:GetPlayers()) do
        if p.Character then
            for _, d in ipairs(p.Character:GetChildren()) do
                if d.Name == "NurHub_ESP" or d.Name == "NurHub_Box3D" then d:Destroy() end
            end
            local head = p.Character:FindFirstChild("Head")
            local bb = head and head:FindFirstChild("NurHub_Billboard")
            if bb then bb:Destroy() end
        end
    end
end

track(workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
    Camera = workspace.CurrentCamera
end))

-- ==========================================================
-- НАСТРОЙКИ
-- ==========================================================
local Config = {
    Visual = {
        ESP = false,            -- главный переключатель
        Outline = true,         -- контур (Highlight)
        ShowNickname = true,
        ShowDistance = true,
        Line = false,
        Box = false,
        Box3D = false,
        DistanceLimit = 500,
        Colors = {
            Outline  = Color3.fromRGB(255, 214, 10),
            Nickname = Color3.fromRGB(255, 255, 255),
            Distance = Color3.fromRGB(64, 200, 224),
            Line     = Color3.fromRGB(255, 69, 58),
            Box      = Color3.fromRGB(48, 209, 88),
            Box3D    = Color3.fromRGB(191, 90, 242),
        }
    },
    Combat = {
        SilentAim = false,
        SilentFOV = 150,
        Aimbot = false,
        AimbotFOV = 200,
        AimbotSmoothness = 0.2,
        VisibleCheck = true
    },
    Player = {
        WalkSpeed = 16,
        JumpPower = 50,
        Noclip = false,
        Fly = false,
        FlySpeed = 50,
        ThirdPerson = false
    }
}

local espObjects = {}
local isMenuOpen = false
local flyBodyVelocity, flyBodyGyro

-- ==========================================================
-- 1. ТЕМА И ХЕЛПЕРЫ
-- ==========================================================

local THEME = {
    Bg = Color3.fromRGB(16, 16, 22),
    Side = Color3.fromRGB(20, 20, 28),
    Card = Color3.fromRGB(28, 28, 38),
    CardHover = Color3.fromRGB(35, 35, 48),
    Stroke = Color3.fromRGB(48, 48, 62),
    Text = Color3.fromRGB(240, 240, 248),
    Dim = Color3.fromRGB(142, 142, 160),
    Accent = Color3.fromRGB(255, 214, 10),
    Accent2 = Color3.fromRGB(255, 140, 0),
    Off = Color3.fromRGB(58, 58, 74),
}

local PALETTE = {
    Color3.fromRGB(255, 214, 10),
    Color3.fromRGB(255, 69, 58),
    Color3.fromRGB(48, 209, 88),
    Color3.fromRGB(64, 200, 224),
    Color3.fromRGB(10, 132, 255),
    Color3.fromRGB(191, 90, 242),
    Color3.fromRGB(255, 255, 255),
}

local function tween(obj, props, time, style, dir)
    local info = TweenInfo.new(time or 0.25, style or Enum.EasingStyle.Quint, dir or Enum.EasingDirection.Out)
    local t = TweenService:Create(obj, info, props)
    t:Play()
    return t
end

local function corner(parent, radius)
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, radius)
    c.Parent = parent
    return c
end

local function addStroke(parent, color, thickness, transparency)
    local s = Instance.new("UIStroke")
    s.Color = color
    s.Thickness = thickness or 1
    s.Transparency = transparency or 0
    s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    s.Parent = parent
    return s
end

local function accentGradient(parent, rotation)
    local g = Instance.new("UIGradient")
    g.Color = ColorSequence.new(THEME.Accent, THEME.Accent2)
    g.Rotation = rotation or 0
    g.Parent = parent
    return g
end

local function makeLabel(parent, text, size, color, font)
    local l = Instance.new("TextLabel")
    l.BackgroundTransparency = 1
    l.Text = text
    l.TextSize = size
    l.TextColor3 = color
    l.Font = font or Enum.Font.Gotham
    l.Parent = parent
    return l
end

local function isPress(input)
    return input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch
end

local function isMove(input)
    return input.UserInputType == Enum.UserInputType.MouseMovement
        or input.UserInputType == Enum.UserInputType.Touch
end

local function makeDraggable(handle, target)
    local dragging, dragStart, startPos = false, nil, nil
    local state = {moved = false}

    track(handle.InputBegan:Connect(function(input)
        if isPress(input) then
            dragging = true
            state.moved = false
            dragStart = input.Position
            startPos = target.Position
            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then dragging = false end
            end)
        end
    end))

    track(UserInputService.InputChanged:Connect(function(input)
        if dragging and isMove(input) then
            local delta = input.Position - dragStart
            if delta.Magnitude > 6 then state.moved = true end
            target.Position = UDim2.new(
                startPos.X.Scale, startPos.X.Offset + delta.X,
                startPos.Y.Scale, startPos.Y.Offset + delta.Y
            )
        end
    end))

    return state
end

-- ==========================================================
-- 2. ИНТЕРФЕЙС
-- ==========================================================

local layoutCounter = 0
local function nextOrder()
    layoutCounter = layoutCounter + 1
    return layoutCounter
end

local function createSlider(parent, y, label, tbl, key, minV, maxV, onChange, scroller)
    local row = Instance.new("Frame")
    row.Size = UDim2.new(1, -28, 0, 38)
    row.Position = UDim2.new(0, 14, 0, y)
    row.BackgroundTransparency = 1
    row.Parent = parent

    local lbl = makeLabel(row, label, 13, THEME.Dim, Enum.Font.Gotham)
    lbl.Size = UDim2.new(0.65, 0, 0, 18)
    lbl.TextXAlignment = Enum.TextXAlignment.Left

    local valLbl = makeLabel(row, tostring(tbl[key]), 13, THEME.Accent, Enum.Font.GothamBold)
    valLbl.Size = UDim2.new(0.35, 0, 0, 18)
    valLbl.Position = UDim2.new(0.65, 0, 0, 0)
    valLbl.TextXAlignment = Enum.TextXAlignment.Right

    local track_ = Instance.new("Frame")
    track_.Size = UDim2.new(1, 0, 0, 6)
    track_.Position = UDim2.new(0, 0, 0, 27)
    track_.BackgroundColor3 = THEME.Off
    track_.BorderSizePixel = 0
    track_.Parent = row
    corner(track_, 3)

    local pct = math.clamp((tbl[key] - minV) / (maxV - minV), 0, 1)

    local fill = Instance.new("Frame")
    fill.Size = UDim2.new(pct, 0, 1, 0)
    fill.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    fill.BorderSizePixel = 0
    fill.Parent = track_
    corner(fill, 3)
    accentGradient(fill, 0)

    local knob = Instance.new("Frame")
    knob.Size = UDim2.new(0, 14, 0, 14)
    knob.Position = UDim2.new(pct, -7, 0.5, -7)
    knob.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    knob.BorderSizePixel = 0
    knob.Parent = track_
    corner(knob, 7)
    addStroke(knob, THEME.Accent, 2)

    local knobScale = Instance.new("UIScale")
    knobScale.Parent = knob

    local hit = Instance.new("TextButton")
    hit.Size = UDim2.new(1, 0, 0, 26)
    hit.Position = UDim2.new(0, 0, 0, 16)
    hit.BackgroundTransparency = 1
    hit.Text = ""
    hit.ZIndex = 2
    hit.Parent = row

    local dragging = false

    local function updateFromX(x)
        local p = math.clamp((x - track_.AbsolutePosition.X) / track_.AbsoluteSize.X, 0, 1)
        fill.Size = UDim2.new(p, 0, 1, 0)
        knob.Position = UDim2.new(p, -7, 0.5, -7)
        local val = math.floor(minV + (maxV - minV) * p + 0.5)
        tbl[key] = val
        valLbl.Text = tostring(val)
        if onChange then onChange(val) end
    end

    track(hit.InputBegan:Connect(function(input)
        if isPress(input) then
            dragging = true
            if scroller then scroller.ScrollingEnabled = false end
            tween(knobScale, {Scale = 1.3}, 0.15)
            updateFromX(input.Position.X)
        end
    end))
    track(UserInputService.InputEnded:Connect(function(input)
        if dragging and isPress(input) then
            dragging = false
            if scroller then scroller.ScrollingEnabled = true end
            tween(knobScale, {Scale = 1}, 0.2)
        end
    end))
    track(UserInputService.InputChanged:Connect(function(input)
        if dragging and isMove(input) then
            updateFromX(input.Position.X)
        end
    end))
end

local function createSection(parent, text)
    local l = makeLabel(parent, text, 12, THEME.Dim, Enum.Font.GothamBold)
    l.Size = UDim2.new(1, 0, 0, 20)
    l.TextXAlignment = Enum.TextXAlignment.Left
    l.LayoutOrder = nextOrder()
    local pad = Instance.new("UIPadding")
    pad.PaddingLeft = UDim.new(0, 4)
    pad.Parent = l
    return l
end

-- opts: {sliders = {{label, tbl, key, min, max, onChange}},
--        palettes = {{tbl = <таблица>, key = "<ключ цвета>"}}, onChange = fn}
local function createToggleCard(parent, title, tbl, key, opts)
    opts = opts or {}
    local sliders = opts.sliders or {}
    local palettes = opts.palettes or {}
    local bodyH = #sliders * 44 + #palettes * 40
    local hasBody = bodyH > 0
    local HEAD = 42

    local card = Instance.new("Frame")
    card.Size = UDim2.new(1, 0, 0, HEAD)
    card.BackgroundColor3 = THEME.Card
    card.ClipsDescendants = true
    card.LayoutOrder = nextOrder()
    card.Parent = parent
    corner(card, 10)
    addStroke(card, THEME.Stroke, 1)

    local head = Instance.new("TextButton")
    head.Size = UDim2.new(1, 0, 0, HEAD)
    head.BackgroundTransparency = 1
    head.Text = ""
    head.AutoButtonColor = false
    head.Parent = card

    local titleLbl = makeLabel(head, title, 14, THEME.Text, Enum.Font.GothamMedium)
    titleLbl.Size = UDim2.new(1, -110, 1, 0)
    titleLbl.Position = UDim2.new(0, 14, 0, 0)
    titleLbl.TextXAlignment = Enum.TextXAlignment.Left

    local chevron
    if hasBody then
        chevron = makeLabel(head, "›", 22, THEME.Dim, Enum.Font.GothamBold)
        chevron.Size = UDim2.new(0, 20, 1, 0)
        chevron.Position = UDim2.new(1, -84, 0, 0)
    end

    local toggle = Instance.new("TextButton")
    toggle.Size = UDim2.new(0, 42, 0, 22)
    toggle.Position = UDim2.new(1, -54, 0.5, -11)
    toggle.Text = ""
    toggle.AutoButtonColor = false
    toggle.Parent = head
    corner(toggle, 11)

    local knob = Instance.new("Frame")
    knob.Size = UDim2.new(0, 16, 0, 16)
    knob.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    knob.BorderSizePixel = 0
    knob.Parent = toggle
    corner(knob, 8)

    local function paint(animate)
        local on = tbl[key]
        local t = animate and 0.22 or 0
        tween(toggle, {BackgroundColor3 = on and THEME.Accent or THEME.Off}, t)
        tween(knob, {Position = on and UDim2.new(0, 23, 0.5, -8) or UDim2.new(0, 3, 0.5, -8)}, t, Enum.EasingStyle.Back)
    end
    paint(false)

    toggle.MouseButton1Click:Connect(function()
        tbl[key] = not tbl[key]
        paint(true)
        if opts.onChange then opts.onChange(tbl[key]) end
    end)

    head.MouseEnter:Connect(function() tween(card, {BackgroundColor3 = THEME.CardHover}, 0.15) end)
    head.MouseLeave:Connect(function() tween(card, {BackgroundColor3 = THEME.Card}, 0.15) end)

    if hasBody then
        local body = Instance.new("Frame")
        body.Size = UDim2.new(1, 0, 0, bodyH)
        body.Position = UDim2.new(0, 0, 0, HEAD)
        body.BackgroundTransparency = 1
        body.Parent = card

        local y = 0
        for _, s in ipairs(sliders) do
            createSlider(body, y, s.label, s.tbl, s.key, s.min, s.max, s.onChange, parent)
            y = y + 44
        end

        for _, pal in ipairs(palettes) do
            local row = Instance.new("Frame")
            row.Size = UDim2.new(1, -28, 0, 32)
            row.Position = UDim2.new(0, 14, 0, y + 4)
            row.BackgroundTransparency = 1
            row.Parent = body
            y = y + 40

            local list = Instance.new("UIListLayout")
            list.FillDirection = Enum.FillDirection.Horizontal
            list.Padding = UDim.new(0, 8)
            list.VerticalAlignment = Enum.VerticalAlignment.Center
            list.Parent = row

            local swatches = {}
            local function refreshRings()
                for _, sw in ipairs(swatches) do
                    tween(sw.ring, {Transparency = (sw.color == pal.tbl[pal.key]) and 0 or 1}, 0.2)
                end
            end

            for _, col in ipairs(PALETTE) do
                local sw = Instance.new("TextButton")
                sw.Size = UDim2.new(0, 24, 0, 24)
                sw.BackgroundColor3 = col
                sw.Text = ""
                sw.AutoButtonColor = false
                sw.Parent = row
                corner(sw, 12)

                local ring = addStroke(sw, Color3.fromRGB(255, 255, 255), 2,
                    (col == pal.tbl[pal.key]) and 0 or 1)
                table.insert(swatches, {color = col, ring = ring})

                sw.MouseButton1Click:Connect(function()
                    pal.tbl[pal.key] = col
                    refreshRings()
                end)
            end
        end

        local open = false
        head.MouseButton1Click:Connect(function()
            open = not open
            tween(card, {Size = UDim2.new(1, 0, 0, open and (HEAD + bodyH + 6) or HEAD)}, 0.32)
            if chevron then
                tween(chevron, {Rotation = open and 90 or 0, TextColor3 = open and THEME.Accent or THEME.Dim}, 0.25)
            end
        end)
    end

    return card
end

local function createSliderCard(parent, label, tbl, key, minV, maxV, onChange)
    local card = Instance.new("Frame")
    card.Size = UDim2.new(1, 0, 0, 54)
    card.BackgroundColor3 = THEME.Card
    card.LayoutOrder = nextOrder()
    card.Parent = parent
    corner(card, 10)
    addStroke(card, THEME.Stroke, 1)
    createSlider(card, 9, label, tbl, key, minV, maxV, onChange, parent)
    return card
end

local function createGUI()
    local guiParent = getGuiParent()
    local old = guiParent:FindFirstChild("NurHubGui")
    if old then old:Destroy() end

    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = "NurHubGui"
    screenGui.ResetOnSpawn = false
    screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    screenGui.DisplayOrder = 10
    screenGui.Parent = guiParent

    local root = Instance.new("Frame")
    root.Name = "Root"
    root.Size = UDim2.new(0, 460, 0, 310)
    root.AnchorPoint = Vector2.new(0.5, 0.5)
    root.Position = UDim2.new(0.5, 0, 0.5, 0)
    root.BackgroundTransparency = 1
    root.Visible = false
    root.Parent = screenGui

    local rootScale = Instance.new("UIScale")
    rootScale.Parent = root

    local shadow = Instance.new("Frame")
    shadow.Size = UDim2.new(1, 20, 1, 20)
    shadow.Position = UDim2.new(0, -10, 0, -6)
    shadow.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
    shadow.BackgroundTransparency = 0.65
    shadow.BorderSizePixel = 0
    shadow.ZIndex = 0
    shadow.Parent = root
    corner(shadow, 22)

    local window = Instance.new("CanvasGroup")
    window.Name = "Window"
    window.Size = UDim2.new(1, 0, 1, 0)
    window.BackgroundColor3 = THEME.Bg
    window.BorderSizePixel = 0
    window.ZIndex = 1
    window.Parent = root
    corner(window, 14)
    addStroke(window, THEME.Stroke, 1)

    local header = Instance.new("Frame")
    header.Size = UDim2.new(1, 0, 0, 44)
    header.BackgroundColor3 = THEME.Side
    header.BorderSizePixel = 0
    header.Parent = window

    local headerLine = Instance.new("Frame")
    headerLine.Size = UDim2.new(1, 0, 0, 1)
    headerLine.Position = UDim2.new(0, 0, 1, -1)
    headerLine.BackgroundColor3 = THEME.Stroke
    headerLine.BorderSizePixel = 0
    headerLine.Parent = header

    local dot = Instance.new("Frame")
    dot.Size = UDim2.new(0, 8, 0, 8)
    dot.Position = UDim2.new(0, 16, 0.5, -4)
    dot.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    dot.BorderSizePixel = 0
    dot.Parent = header
    corner(dot, 4)
    accentGradient(dot, 45)

    local title = makeLabel(header, 'Nur<font color="rgb(255,214,10)">Hub</font>', 18, THEME.Text, Enum.Font.GothamBold)
    title.RichText = true
    title.Size = UDim2.new(0, 80, 1, 0)
    title.Position = UDim2.new(0, 32, 0, 0)
    title.TextXAlignment = Enum.TextXAlignment.Left

    local ver = makeLabel(header, "v1.1", 12, THEME.Dim, Enum.Font.Gotham)
    ver.Size = UDim2.new(0, 40, 1, 0)
    ver.Position = UDim2.new(0, 104, 0, 1)
    ver.TextXAlignment = Enum.TextXAlignment.Left

    local closeBtn = Instance.new("TextButton")
    closeBtn.Size = UDim2.new(0, 30, 0, 30)
    closeBtn.Position = UDim2.new(1, -40, 0.5, -15)
    closeBtn.BackgroundColor3 = THEME.Card
    closeBtn.Text = "×"
    closeBtn.TextSize = 22
    closeBtn.TextColor3 = THEME.Dim
    closeBtn.Font = Enum.Font.GothamBold
    closeBtn.AutoButtonColor = false
    closeBtn.Parent = header
    corner(closeBtn, 8)

    closeBtn.MouseEnter:Connect(function()
        tween(closeBtn, {BackgroundColor3 = Color3.fromRGB(255, 69, 58), TextColor3 = Color3.fromRGB(255, 255, 255)}, 0.15)
    end)
    closeBtn.MouseLeave:Connect(function()
        tween(closeBtn, {BackgroundColor3 = THEME.Card, TextColor3 = THEME.Dim}, 0.15)
    end)

    local sidebar = Instance.new("Frame")
    sidebar.Size = UDim2.new(0, 118, 1, -44)
    sidebar.Position = UDim2.new(0, 0, 0, 44)
    sidebar.BackgroundColor3 = THEME.Side
    sidebar.BorderSizePixel = 0
    sidebar.Parent = window

    local sideLine = Instance.new("Frame")
    sideLine.Size = UDim2.new(0, 1, 1, 0)
    sideLine.Position = UDim2.new(1, -1, 0, 0)
    sideLine.BackgroundColor3 = THEME.Stroke
    sideLine.BorderSizePixel = 0
    sideLine.Parent = sidebar

    local indicator = Instance.new("Frame")
    indicator.Size = UDim2.new(0, 3, 0, 18)
    indicator.Position = UDim2.new(0, 2, 0, 19)
    indicator.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    indicator.BorderSizePixel = 0
    indicator.Parent = sidebar
    corner(indicator, 2)
    accentGradient(indicator, 90)

    local content = Instance.new("Frame")
    content.Size = UDim2.new(1, -118, 1, -44)
    content.Position = UDim2.new(0, 118, 0, 44)
    content.BackgroundTransparency = 1
    content.Parent = window

    local pages, tabButtons, tabIndex = {}, {}, {}

    local function createPage(name)
        local page = Instance.new("CanvasGroup")
        page.Size = UDim2.new(1, 0, 1, 0)
        page.BackgroundTransparency = 1
        page.Visible = false
        page.Parent = content

        local scroll = Instance.new("ScrollingFrame")
        scroll.Size = UDim2.new(1, 0, 1, 0)
        scroll.BackgroundTransparency = 1
        scroll.BorderSizePixel = 0
        scroll.ScrollBarThickness = 3
        scroll.ScrollBarImageColor3 = THEME.Accent
        scroll.ScrollingDirection = Enum.ScrollingDirection.Y
        scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
        scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
        scroll.Parent = page

        local layout = Instance.new("UIListLayout")
        layout.Padding = UDim.new(0, 8)
        layout.SortOrder = Enum.SortOrder.LayoutOrder
        layout.Parent = scroll

        local pad = Instance.new("UIPadding")
        pad.PaddingTop = UDim.new(0, 10)
        pad.PaddingBottom = UDim.new(0, 12)
        pad.PaddingLeft = UDim.new(0, 12)
        pad.PaddingRight = UDim.new(0, 14)
        pad.Parent = scroll

        pages[name] = page
        return scroll
    end

    local tabNames = {"Visual", "Combat", "Player"}
    local currentTab

    local function selectTab(name, animate)
        if currentTab == name then return end
        currentTab = name
        local t = animate and 0.25 or 0

        for n, b in pairs(tabButtons) do
            local sel = (n == name)
            tween(b, {BackgroundTransparency = sel and 0.88 or 1, TextColor3 = sel and THEME.Accent or THEME.Dim}, t)
        end
        tween(indicator, {Position = UDim2.new(0, 2, 0, 10 + (tabIndex[name] - 1) * 42 + 9)}, t, Enum.EasingStyle.Back)

        for n, p in pairs(pages) do
            if n == name then
                p.Visible = true
                if animate then
                    p.GroupTransparency = 1
                    p.Position = UDim2.new(0, 0, 0, 14)
                    tween(p, {GroupTransparency = 0, Position = UDim2.new(0, 0, 0, 0)}, 0.3)
                else
                    p.GroupTransparency = 0
                    p.Position = UDim2.new(0, 0, 0, 0)
                end
            else
                p.Visible = false
            end
        end
    end

    for i, name in ipairs(tabNames) do
        tabIndex[name] = i

        local btn = Instance.new("TextButton")
        btn.Size = UDim2.new(1, -18, 0, 36)
        btn.Position = UDim2.new(0, 10, 0, 10 + (i - 1) * 42)
        btn.BackgroundColor3 = THEME.Accent
        btn.BackgroundTransparency = 1
        btn.Text = name
        btn.TextSize = 14
        btn.TextColor3 = THEME.Dim
        btn.Font = Enum.Font.GothamMedium
        btn.TextXAlignment = Enum.TextXAlignment.Left
        btn.AutoButtonColor = false
        btn.Parent = sidebar
        corner(btn, 8)

        local pad = Instance.new("UIPadding")
        pad.PaddingLeft = UDim.new(0, 14)
        pad.Parent = btn

        tabButtons[name] = btn
        btn.MouseButton1Click:Connect(function() selectTab(name, true) end)
    end

    -- ===== Страница Visual =====
    local V = Config.Visual
    local vis = createPage("Visual")
    createSection(vis, "ESP")
    createToggleCard(vis, "ESP (включить всё)", V, "ESP", {
        sliders = {
            {label = "Дистанция ESP", tbl = V, key = "DistanceLimit", min = 50, max = 2000}
        }
    })
    createSection(vis, "Элементы ESP")
    createToggleCard(vis, "Контур (Outline)", V, "Outline",
        {palettes = {{tbl = V.Colors, key = "Outline"}}})
    createToggleCard(vis, "Show Nickname", V, "ShowNickname",
        {palettes = {{tbl = V.Colors, key = "Nickname"}}})
    createToggleCard(vis, "Show Distance", V, "ShowDistance",
        {palettes = {{tbl = V.Colors, key = "Distance"}}})
    createToggleCard(vis, "Line", V, "Line",
        {palettes = {{tbl = V.Colors, key = "Line"}}})
    createToggleCard(vis, "Box", V, "Box",
        {palettes = {{tbl = V.Colors, key = "Box"}}})
    createToggleCard(vis, "3D Box", V, "Box3D",
        {palettes = {{tbl = V.Colors, key = "Box3D"}}})

    -- ===== Страница Combat =====
    local com = createPage("Combat")
    createSection(com, "Прицеливание")
    local smoothProxy = {v = math.floor(Config.Combat.AimbotSmoothness * 100 + 0.5)}
    createToggleCard(com, "Aimbot", Config.Combat, "Aimbot", {
        sliders = {
            {label = "FOV аимбота", tbl = Config.Combat, key = "AimbotFOV", min = 30, max = 500},
            {label = "Скорость наводки %", tbl = smoothProxy, key = "v", min = 1, max = 100,
                onChange = function(v) Config.Combat.AimbotSmoothness = v / 100 end}
        }
    })
    createToggleCard(com, "Silent Aim", Config.Combat, "SilentAim", {
        sliders = {
            {label = "FOV silent aim", tbl = Config.Combat, key = "SilentFOV", min = 30, max = 500}
        }
    })
    createToggleCard(com, "Проверка видимости", Config.Combat, "VisibleCheck")

    -- ===== Страница Player =====
    local plr = createPage("Player")
    createSection(plr, "Движение")
    createSliderCard(plr, "WalkSpeed", Config.Player, "WalkSpeed", 16, 200)
    createSliderCard(plr, "JumpPower", Config.Player, "JumpPower", 50, 300)
    createToggleCard(plr, "Noclip", Config.Player, "Noclip")
    createToggleCard(plr, "Fly", Config.Player, "Fly", {
        sliders = {
            {label = "Скорость полёта", tbl = Config.Player, key = "FlySpeed", min = 10, max = 200}
        }
    })
    createSection(plr, "Камера")
    createToggleCard(plr, "Third Person", Config.Player, "ThirdPerson", {
        onChange = function(on)
            if on then
                LocalPlayer.CameraMode = Enum.CameraMode.Classic
                LocalPlayer.CameraMaxZoomDistance = 128
                LocalPlayer.CameraMinZoomDistance = 0.5
            else
                LocalPlayer.CameraMaxZoomDistance = 0.5
            end
        end
    })

    selectTab("Visual", false)

    -- ===== Кнопка-лаунчер =====
    local launcher = Instance.new("TextButton")
    launcher.Name = "Launcher"
    launcher.Size = UDim2.new(0, 48, 0, 48)
    launcher.Position = UDim2.new(0.06, 0, 0.5, 0)
    launcher.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    launcher.Text = "N"
    launcher.TextSize = 24
    launcher.TextColor3 = Color3.fromRGB(20, 20, 20)
    launcher.Font = Enum.Font.GothamBlack
    launcher.AutoButtonColor = false
    launcher.Parent = screenGui
    corner(launcher, 24)
    accentGradient(launcher, 45)
    addStroke(launcher, Color3.fromRGB(255, 255, 255), 2, 0.6)

    local launcherScale = Instance.new("UIScale")
    launcherScale.Parent = launcher

    launcher.MouseEnter:Connect(function() tween(launcherScale, {Scale = 1.1}, 0.15) end)
    launcher.MouseLeave:Connect(function() tween(launcherScale, {Scale = 1}, 0.15) end)
    launcher.MouseButton1Down:Connect(function() tween(launcherScale, {Scale = 0.92}, 0.1) end)
    launcher.MouseButton1Up:Connect(function() tween(launcherScale, {Scale = 1}, 0.15, Enum.EasingStyle.Back) end)

    local launcherDrag = makeDraggable(launcher, launcher)
    makeDraggable(header, root)

    local function setMenu(open)
        isMenuOpen = open
        if open then
            local vp = Camera.ViewportSize
            local fit = math.min(1, (vp.X - 20) / 460, (vp.Y - 20) / 310)
            fit = math.max(fit, 0.4)

            root.Visible = true
            rootScale.Scale = fit * 0.85
            window.GroupTransparency = 1
            shadow.BackgroundTransparency = 1

            tween(rootScale, {Scale = fit}, 0.4, Enum.EasingStyle.Back)
            tween(window, {GroupTransparency = 0}, 0.25)
            tween(shadow, {BackgroundTransparency = 0.65}, 0.35)
        else
            tween(rootScale, {Scale = rootScale.Scale * 0.92}, 0.2)
            tween(window, {GroupTransparency = 1}, 0.2)
            tween(shadow, {BackgroundTransparency = 1}, 0.2)
            task.delay(0.22, function()
                if not isMenuOpen then root.Visible = false end
            end)
        end
    end

    launcher.MouseButton1Click:Connect(function()
        if launcherDrag.moved then launcherDrag.moved = false return end
        setMenu(not isMenuOpen)
    end)
    closeBtn.MouseButton1Click:Connect(function() setMenu(false) end)

    track(UserInputService.InputBegan:Connect(function(input, processed)
        if not processed and input.KeyCode == Enum.KeyCode.RightShift then
            setMenu(not isMenuOpen)
        end
    end))
end

createGUI()

-- ==========================================================
-- 3. ВИЗУАЛЬНАЯ ЧАСТЬ (ESP без Drawing)
--    Outline  -> Highlight
--    Nick/Dist-> BillboardGui
--    3D Box   -> SelectionBox
--    Box/Line -> Frame'ы на отдельном ScreenGui
-- ==========================================================

local espGui = Instance.new("ScreenGui")
espGui.Name = "NurHubESPGui"
espGui.ResetOnSpawn = false
espGui.IgnoreGuiInset = true
espGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
espGui.DisplayOrder = 1
espGui.Parent = getGuiParent()

local function clearESP(player)
    local obj = espObjects[player]
    if obj then
        for _, k in ipairs({"Highlight", "Billboard", "Selection", "BoxFrame", "LineFrame"}) do
            if obj[k] then pcall(function() obj[k]:Destroy() end) end
        end
        espObjects[player] = nil
    end
end

local function createESP(player, char, head)
    local highlight = Instance.new("Highlight")
    highlight.Name = "NurHub_ESP"
    highlight.FillTransparency = 1
    highlight.OutlineTransparency = 0
    highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    highlight.Adornee = char
    highlight.Enabled = false
    highlight.Parent = char

    local selection = Instance.new("SelectionBox")
    selection.Name = "NurHub_Box3D"
    selection.LineThickness = 0.04
    selection.SurfaceTransparency = 1
    selection.Adornee = nil
    selection.Parent = char

    local billboard = Instance.new("BillboardGui")
    billboard.Name = "NurHub_Billboard"
    billboard.Size = UDim2.new(0, 200, 0, 40)
    billboard.StudsOffset = Vector3.new(0, 3, 0)
    billboard.AlwaysOnTop = true
    billboard.Enabled = false
    billboard.Parent = head

    local list = Instance.new("UIListLayout")
    list.SortOrder = Enum.SortOrder.LayoutOrder
    list.Parent = billboard

    local nickname = Instance.new("TextLabel")
    nickname.Name = "Nickname"
    nickname.Size = UDim2.new(1, 0, 0, 20)
    nickname.LayoutOrder = 1
    nickname.BackgroundTransparency = 1
    nickname.Text = player.DisplayName
    nickname.TextStrokeTransparency = 0
    nickname.Font = Enum.Font.GothamBold
    nickname.TextSize = 14
    nickname.Parent = billboard

    local distance = Instance.new("TextLabel")
    distance.Name = "Distance"
    distance.Size = UDim2.new(1, 0, 0, 20)
    distance.LayoutOrder = 2
    distance.BackgroundTransparency = 1
    distance.TextStrokeTransparency = 0
    distance.Font = Enum.Font.Gotham
    distance.TextSize = 13
    distance.Parent = billboard

    -- 2D Box
    local boxFrame = Instance.new("Frame")
    boxFrame.BackgroundTransparency = 1
    boxFrame.BorderSizePixel = 0
    boxFrame.Visible = false
    boxFrame.Parent = espGui
    local boxStroke = Instance.new("UIStroke")
    boxStroke.Thickness = 1.5
    boxStroke.Parent = boxFrame

    -- Line
    local lineFrame = Instance.new("Frame")
    lineFrame.AnchorPoint = Vector2.new(0.5, 0.5)
    lineFrame.BorderSizePixel = 0
    lineFrame.Visible = false
    lineFrame.Parent = espGui

    local obj = {
        Char = char, Highlight = highlight, Selection = selection,
        Billboard = billboard, Nickname = nickname, Distance = distance,
        BoxFrame = boxFrame, BoxStroke = boxStroke, LineFrame = lineFrame,
    }
    espObjects[player] = obj
    return obj
end

local function hideAll(obj)
    obj.Highlight.Enabled = false
    obj.Billboard.Enabled = false
    obj.Selection.Adornee = nil
    obj.BoxFrame.Visible = false
    obj.LineFrame.Visible = false
end

local function updateESP()
    local V = Config.Visual
    local C = V.Colors
    local myChar = LocalPlayer.Character
    local myHrp = myChar and myChar:FindFirstChild("HumanoidRootPart")
    local vp = Camera.ViewportSize

    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer then
            local char = player.Character
            local hrp = char and char:FindFirstChild("HumanoidRootPart")
            local head = char and char:FindFirstChild("Head")
            local hum = char and char:FindFirstChildOfClass("Humanoid")
            local obj = espObjects[player]

            if not (hrp and head and hum) then
                if obj then clearESP(player) end
            else
                if obj and (obj.Char ~= char or not obj.Highlight.Parent or not obj.Billboard.Parent) then
                    clearESP(player)
                    obj = nil
                end
                if not obj then obj = createESP(player, char, head) end

                local origin = myHrp and myHrp.Position or Camera.CFrame.Position
                local dist = (hrp.Position - origin).Magnitude
                local show = V.ESP and hum.Health > 0 and dist <= V.DistanceLimit

                if not show then
                    hideAll(obj)
                else
                    -- Outline
                    obj.Highlight.Enabled = V.Outline
                    obj.Highlight.OutlineColor = C.Outline

                    -- Nickname / Distance
                    obj.Billboard.Enabled = V.ShowNickname or V.ShowDistance
                    obj.Nickname.Visible = V.ShowNickname
                    obj.Nickname.TextColor3 = C.Nickname
                    obj.Distance.Visible = V.ShowDistance
                    obj.Distance.TextColor3 = C.Distance
                    if V.ShowDistance then
                        obj.Distance.Text = math.floor(dist) .. " studs"
                    end

                    -- 3D Box
                    if V.Box3D then
                        obj.Selection.Color3 = C.Box3D
                        obj.Selection.Adornee = char
                    else
                        obj.Selection.Adornee = nil
                    end

                    -- 2D Box + Line (проекция bounding box на экран)
                    local boxOn, lineOn = false, false
                    if V.Box or V.Line then
                        local cf, size = char:GetBoundingBox()
                        local minX, minY, maxX, maxY = math.huge, math.huge, -math.huge, -math.huge
                        local allFront = true
                        for i = 0, 7 do
                            local sx = (i % 2 == 0) and 1 or -1
                            local sy = (math.floor(i / 2) % 2 == 0) and 1 or -1
                            local sz = (math.floor(i / 4) % 2 == 0) and 1 or -1
                            local wp = (cf * CFrame.new(size.X / 2 * sx, size.Y / 2 * sy, size.Z / 2 * sz)).Position
                            local p = Camera:WorldToViewportPoint(wp)
                            if p.Z <= 0 then allFront = false break end
                            minX = math.min(minX, p.X); maxX = math.max(maxX, p.X)
                            minY = math.min(minY, p.Y); maxY = math.max(maxY, p.Y)
                        end

                        if allFront then
                            if V.Box then
                                boxOn = true
                                obj.BoxFrame.Position = UDim2.fromOffset(minX, minY)
                                obj.BoxFrame.Size = UDim2.fromOffset(maxX - minX, maxY - minY)
                                obj.BoxStroke.Color = C.Box
                            end
                            if V.Line then
                                lineOn = true
                                local a = Vector2.new(vp.X / 2, vp.Y)
                                local b = Vector2.new((minX + maxX) / 2, maxY)
                                local d = b - a
                                obj.LineFrame.BackgroundColor3 = C.Line
                                obj.LineFrame.Size = UDim2.fromOffset(d.Magnitude, 2)
                                obj.LineFrame.Position = UDim2.fromOffset((a.X + b.X) / 2, (a.Y + b.Y) / 2)
                                obj.LineFrame.Rotation = math.deg(math.atan2(d.Y, d.X))
                            end
                        end
                    end
                    obj.BoxFrame.Visible = boxOn
                    obj.LineFrame.Visible = lineOn
                end
            end
        end
    end
end

-- ==========================================================
-- 4. БОЕВАЯ ЧАСТЬ (COMBAT)
-- ==========================================================

local function getAimPoint()
    if UserInputService.TouchEnabled and not UserInputService.MouseEnabled then
        return Camera.ViewportSize / 2
    end
    return UserInputService:GetMouseLocation()
end

local function isVisible(targetPart)
    if not Config.Combat.VisibleCheck then return true end
    local ignore = {targetPart.Parent}
    if LocalPlayer.Character then table.insert(ignore, LocalPlayer.Character) end

    local params = RaycastParams.new()
    params.FilterDescendantsInstances = ignore
    params.FilterType = Enum.RaycastFilterType.Exclude

    local origin = Camera.CFrame.Position
    local result = workspace:Raycast(origin, targetPart.Position - origin, params)
    return result == nil
end

local function getTarget(fov)
    local closest, shortest = nil, fov
    local aimPoint = getAimPoint()

    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer and player.Character then
            local head = player.Character:FindFirstChild("Head")
            local hum = player.Character:FindFirstChildOfClass("Humanoid")
            if head and hum and hum.Health > 0 then
                local sp, onScreen = Camera:WorldToViewportPoint(head.Position)
                if onScreen then
                    local d = (Vector2.new(sp.X, sp.Y) - aimPoint).Magnitude
                    if d < shortest and isVisible(head) then
                        shortest = d
                        closest = head
                    end
                end
            end
        end
    end
    return closest
end

-- ==========================================================
-- 5. ИГРОК (PLAYER)
-- ==========================================================

local modded = {speed = false, jump = false}

local function applyPlayerMods()
    local char = LocalPlayer.Character
    local humanoid = char and char:FindFirstChildOfClass("Humanoid")
    if not humanoid then return end

    -- Значение по умолчанию тоже применяется один раз, чтобы можно было вернуть скорость назад
    if Config.Player.WalkSpeed ~= 16 then
        modded.speed = true
        if humanoid.WalkSpeed ~= Config.Player.WalkSpeed then
            humanoid.WalkSpeed = Config.Player.WalkSpeed
        end
    elseif modded.speed then
        modded.speed = false
        humanoid.WalkSpeed = 16
    end

    if Config.Player.JumpPower ~= 50 then
        modded.jump = true
        humanoid.UseJumpPower = true
        if humanoid.JumpPower ~= Config.Player.JumpPower then
            humanoid.JumpPower = Config.Player.JumpPower
        end
    elseif modded.jump then
        modded.jump = false
        humanoid.UseJumpPower = true
        humanoid.JumpPower = 50
    end
end

local wasNoclip = false
track(RunService.Stepped:Connect(function()
    local char = LocalPlayer.Character
    if not char then return end
    if Config.Player.Noclip then
        wasNoclip = true
        for _, part in ipairs(char:GetDescendants()) do
            if part:IsA("BasePart") then
                part.CanCollide = false
            end
        end
    elseif wasNoclip then
        wasNoclip = false
        local hrp = char:FindFirstChild("HumanoidRootPart")
        if hrp then hrp.CanCollide = true end
    end
end))

local function stopFly()
    if flyBodyVelocity then flyBodyVelocity:Destroy() flyBodyVelocity = nil end
    if flyBodyGyro then flyBodyGyro:Destroy() flyBodyGyro = nil end
    local char = LocalPlayer.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if hum then hum.PlatformStand = false end
end

local function updateFly()
    local char = LocalPlayer.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if not (hrp and hum) then return end

    if Config.Player.Fly then
        if not flyBodyVelocity or flyBodyVelocity.Parent ~= hrp then
            stopFly()
            flyBodyVelocity = Instance.new("BodyVelocity")
            flyBodyVelocity.MaxForce = Vector3.new(1e5, 1e5, 1e5)
            flyBodyVelocity.Velocity = Vector3.zero
            flyBodyVelocity.Parent = hrp

            flyBodyGyro = Instance.new("BodyGyro")
            flyBodyGyro.MaxTorque = Vector3.new(1e5, 1e5, 1e5)
            flyBodyGyro.P = 1000
            flyBodyGyro.Parent = hrp
        end

        hum.PlatformStand = true
        local moveLocal = Camera.CFrame:VectorToObjectSpace(hum.MoveDirection)
        local dir = Camera.CFrame:VectorToWorldSpace(Vector3.new(moveLocal.X, 0, moveLocal.Z))
        if dir.Magnitude > 0 then dir = dir.Unit end

        flyBodyVelocity.Velocity = dir * Config.Player.FlySpeed
        flyBodyGyro.CFrame = Camera.CFrame
    elseif flyBodyVelocity or flyBodyGyro then
        stopFly()
    end
end

track(LocalPlayer.CharacterAdded:Connect(function()
    flyBodyVelocity, flyBodyGyro = nil, nil
    modded.speed, modded.jump = false, false
end))

-- ==========================================================
-- 6. ГЛАВНЫЙ ЦИКЛ
-- ==========================================================

RunService:BindToRenderStep("NurHubLoop", Enum.RenderPriority.Camera.Value + 1, function()
    pcall(updateESP)

    pcall(function()
        if Config.Combat.Aimbot then
            local target = getTarget(Config.Combat.AimbotFOV)
            if target then
                local cur = Camera.CFrame
                Camera.CFrame = cur:Lerp(CFrame.new(cur.Position, target.Position), Config.Combat.AimbotSmoothness)
            end
        end

        if Config.Combat.SilentAim then
            -- Упрощённая версия: настоящий silent aim требует хука на уровне игры
            local target = getTarget(Config.Combat.SilentFOV)
            if target then
                local cur = Camera.CFrame
                Camera.CFrame = cur:Lerp(CFrame.new(cur.Position, target.Position), 0.5)
            end
        end
    end)

    pcall(applyPlayerMods)
    pcall(updateFly)
end)

track(Players.PlayerRemoving:Connect(clearESP))

pcall(function()
    game:GetService("StarterGui"):SetCore("SendNotification", {
        Title = "NurHub",
        Text = "Скрипт успешно загружен!",
        Duration = 5
    })
end)
