local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local HttpService = game:GetService("HttpService")
local CoreGui = game:GetService("CoreGui")

local LocalPlayer = Players.LocalPlayer

local LiquidUI = {}
LiquidUI.__index = LiquidUI
LiquidUI.Version = "2.1.0"

LiquidUI.Theme = {
	Background = Color3.fromRGB(15,16,20),
	BackgroundTop = Color3.fromRGB(20,21,26),
	Sidebar = Color3.fromRGB(17,18,22),
	Surface = Color3.fromRGB(29,30,36),
	SurfaceHover = Color3.fromRGB(38,40,47),
	SurfacePressed = Color3.fromRGB(45,47,56),
	Text = Color3.fromRGB(242,243,247),
	SubText = Color3.fromRGB(151,154,164),
	Muted = Color3.fromRGB(103,106,116),
	Accent = Color3.fromRGB(43,148,255),
	AccentBright = Color3.fromRGB(75,173,255),
	Red = Color3.fromRGB(239,76,82),
	Green = Color3.fromRGB(63,205,128),
	Yellow = Color3.fromRGB(246,196,68),
	White = Color3.fromRGB(255,255,255)
}

--// ---------------------------------------------------------------------
--// Generic helpers
--// ---------------------------------------------------------------------

local function New(class,props,parent)
	local object = Instance.new(class)
	for property,value in pairs(props or {}) do
		object[property] = value
	end
	object.Parent = parent
	return object
end

local function Corner(object,radius)
	return New("UICorner",{
		CornerRadius = UDim.new(0,radius or 10)
	},object)
end

local function Stroke(object,transparency,thickness)
	return New("UIStroke",{
		Color = LiquidUI.Theme.White,
		Transparency = transparency or .92,
		Thickness = thickness or 1
	},object)
end

local function Padding(object,left,right,top,bottom)
	return New("UIPadding",{
		PaddingLeft = UDim.new(0,left or 0),
		PaddingRight = UDim.new(0,right or 0),
		PaddingTop = UDim.new(0,top or 0),
		PaddingBottom = UDim.new(0,bottom or 0)
	},object)
end

local function Tween(object,properties,duration)
	local tween = TweenService:Create(
		object,
		TweenInfo.new(
			duration or .16,
			Enum.EasingStyle.Quint,
			Enum.EasingDirection.Out
		),
		properties
	)
	tween:Play()
	return tween
end

local function protectGui(gui)
	local protected = false

	pcall(function()
		if syn and syn.protect_gui then
			syn.protect_gui(gui)
			protected = true
		end
	end)

	pcall(function()
		if not protected and gethui then
			gui.Parent = gethui()
			protected = true
		end
	end)

	if not protected then
		gui.Parent = CoreGui
	end
end

--// ---------------------------------------------------------------------
--// Icons -- loaded asynchronously so the window never blocks (or breaks)
--// waiting on a network request. Anything that requests an icon before
--// the data has arrived gets a themed placeholder that is swapped for
--// the real icon the moment (if ever) the fetch succeeds.
--// ---------------------------------------------------------------------

local IconData = nil
local IconLoadAttempted = false
local IconLoadFinished = false
local PendingIconRequests = {} -- {imageLabel=ImageLabel, name=string, color=Color3}

local function fetchIconModule()
	local urls = {
		"https://raw.githubusercontent.com/Footagesus/Icons/refs/heads/main/lucide/dist/Icons.lua",
		"https://raw.githubusercontent.com/Footagesus/Icons/main/lucide/dist/Icons.lua"
	}

	for _,url in ipairs(urls) do
		local ok,result = pcall(function()
			if game.HttpGet then
				return game:HttpGet(url)
			end
			return HttpService:GetAsync(url)
		end)

		if ok and type(result) == "string" and #result > 50 then
			local load = loadstring or load
			local compileOk,module = pcall(load,result)
			if compileOk and type(module) == "function" then
				local runOk,data = pcall(module)
				if runOk and type(data) == "table" then
					return data
				end
			end
		end
	end

	return nil
end

local function resolveIcon(name)
	if not name or name == "" or type(IconData) ~= "table" then
		return nil
	end

	local iconType,iconName = tostring(name):match("^([^:]+):(.+)$")
	iconType = iconType or "lucide"
	iconName = iconName or tostring(name)

	if iconType ~= "lucide" then
		return nil
	end

	-- Supports the common Footagesus/Icons return layouts.
	if IconData.Icons and IconData.Icons[iconName] then
		local data = IconData.Icons[iconName]
		if type(data) == "table" then
			local image = data.Image or data[1]
			if image then
				return {
					Image = image,
					ImageRectSize = data.ImageRectSize,
					ImageRectPosition = data.ImageRectPosition
				}
			end
		end
	end

	if IconData[iconName] then
		local data = IconData[iconName]
		if type(data) == "string" then
			return {Image=data}
		elseif type(data) == "table" then
			return {
				Image = data.Image or data[1],
				ImageRectSize = data.ImageRectSize or (data[2] and data[2].ImageRectSize),
				ImageRectPosition = data.ImageRectPosition or (data[2] and data[2].ImageRectPosition)
			}
		end
	end

	return nil
end

local function applyIconData(imageLabel,name,color)
	local data = resolveIcon(name)
	if not data or not data.Image then
		return false
	end

	imageLabel.Image = data.Image
	imageLabel.ImageColor3 = color or LiquidUI.Theme.SubText

	if data.ImageRectSize and data.ImageRectSize.X > 0 then
		imageLabel.ImageRectSize = data.ImageRectSize
		imageLabel.ImageRectOffset = data.ImageRectPosition or Vector2.zero
	end

	-- Hide the placeholder dot behind it, if any.
	local dot = imageLabel:FindFirstChild("__Placeholder")
	if dot then
		dot.Visible = false
	end

	return true
end

local function beginIconLoad()
	if IconLoadAttempted then
		return
	end
	IconLoadAttempted = true

	task.spawn(function()
		IconData = fetchIconModule()
		IconLoadFinished = true

		for _,request in ipairs(PendingIconRequests) do
			if request.imageLabel and request.imageLabel.Parent then
				applyIconData(request.imageLabel,request.name,request.color)
			end
		end
		PendingIconRequests = {}
	end)
end

-- Creates an icon slot immediately (with a small themed placeholder dot),
-- and upgrades it to the real vector icon once/if the icon pack loads.
local function createIcon(parent,name,size,color)
	if not name or name == "" then
		return nil
	end

	beginIconLoad()

	size = size or 18
	color = color or LiquidUI.Theme.SubText

	local image = New("ImageLabel",{
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(size,size),
		Image = "",
		ImageColor3 = color,
		ScaleType = Enum.ScaleType.Fit
	},parent)

	local placeholder = New("Frame",{
		Name = "__Placeholder",
		Size = UDim2.fromScale(.5,.5),
		AnchorPoint = Vector2.new(.5,.5),
		Position = UDim2.fromScale(.5,.5),
		BackgroundColor3 = color,
		BackgroundTransparency = .35,
		BorderSizePixel = 0
	},image)
	Corner(placeholder,100)

	if IconLoadFinished then
		applyIconData(image,name,color)
	elseif type(IconData) == "table" then
		applyIconData(image,name,color)
	else
		table.insert(PendingIconRequests,{imageLabel=image,name=name,color=color})
	end

	return image
end

local function createShadow(parent)
	local shadow = New("ImageLabel",{
		Name = "Shadow",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(-28,-28),
		Size = UDim2.new(1,56,1,56),
		Image = "rbxassetid://6014261993",
		ImageColor3 = Color3.fromRGB(0,0,0),
		ImageTransparency = .28,
		ScaleType = Enum.ScaleType.Slice,
		SliceCenter = Rect.new(49,49,450,450),
		ZIndex = 0
	},parent)
	return shadow
end

--// ---------------------------------------------------------------------
--// Window
--// ---------------------------------------------------------------------

function LiquidUI:CreateWindow(config)
	config = config or {}

	local self = setmetatable({},LiquidUI)

	self.Config = config
	self.Title = config.Title or "LiquidUI"
	self.Subtitle = config.Subtitle or "Modern Roblox interface"
	self.ToggleKey = config.ToggleKey or Enum.KeyCode.LeftControl
	self.Size = config.Size or UDim2.fromOffset(760,500)
	self.MinSize = config.MinSize or Vector2.new(620,400)
	self.MaxSize = config.MaxSize or Vector2.new(1250,800)
	self.Tabs = {}
	self.ActiveTab = nil
	self.Visible = true
	self.SidebarCollapsed = false
	self.Connections = {}
	self.Destroyed = false

	local guiName = config.Name or "LiquidUI"

	local old
	pcall(function()
		old = (gethui and gethui() or CoreGui):FindFirstChild(guiName)
	end)
	if old then
		old:Destroy()
	end

	self.Gui = New("ScreenGui",{
		Name = guiName,
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	})
	protectGui(self.Gui)

	self.Container = New("Frame",{
		Name = "Container",
		AnchorPoint = Vector2.new(.5,.5),
		Position = UDim2.fromScale(.5,.5),
		Size = self.Size,
		BackgroundTransparency = 1
	},self.Gui)

	self.Shadow = createShadow(self.Container)

	self.Window = New("Frame",{
		Name = "Window",
		Size = UDim2.fromScale(1,1),
		BackgroundColor3 = LiquidUI.Theme.Background,
		BorderSizePixel = 0,
		ClipsDescendants = true,
		ZIndex = 2
	},self.Container)
	Corner(self.Window,16)
	Stroke(self.Window,.88,1)

	New("UIGradient",{
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0,LiquidUI.Theme.BackgroundTop),
			ColorSequenceKeypoint.new(.45,LiquidUI.Theme.Background),
			ColorSequenceKeypoint.new(1,Color3.fromRGB(12,13,17))
		}),
		Rotation = 125
	},self.Window)

	New("UISizeConstraint",{
		MinSize = self.MinSize,
		MaxSize = self.MaxSize
	},self.Container)

	-- Topbar ---------------------------------------------------------

	self.Topbar = New("Frame",{
		Name = "Topbar",
		Size = UDim2.new(1,0,0,62),
		BackgroundColor3 = Color3.fromRGB(18,19,24),
		BackgroundTransparency = .12,
		BorderSizePixel = 0,
		ZIndex = 5
	},self.Window)

	local titleIconHolder = New("Frame",{
		Position = UDim2.fromOffset(15,12),
		Size = UDim2.fromOffset(38,38),
		BackgroundColor3 = LiquidUI.Theme.Surface,
		BorderSizePixel = 0,
		ZIndex = 6
	},self.Topbar)
	Corner(titleIconHolder,11)

	local titleIcon = createIcon(
		titleIconHolder,
		config.Icon or "lucide:wrench",
		19,
		LiquidUI.Theme.AccentBright
	)
	if titleIcon then
		titleIcon.AnchorPoint = Vector2.new(.5,.5)
		titleIcon.Position = UDim2.fromScale(.5,.5)
	end

	New("TextLabel",{
		Position = UDim2.fromOffset(64,10),
		Size = UDim2.new(1,-260,0,22),
		BackgroundTransparency = 1,
		Text = self.Title,
		TextColor3 = LiquidUI.Theme.Text,
		TextSize = 14,
		Font = Enum.Font.GothamBold,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		ZIndex = 6
	},self.Topbar)

	New("TextLabel",{
		Position = UDim2.fromOffset(64,32),
		Size = UDim2.new(1,-260,0,16),
		BackgroundTransparency = 1,
		Text = self.Subtitle,
		TextColor3 = LiquidUI.Theme.SubText,
		TextSize = 9,
		Font = Enum.Font.Gotham,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		ZIndex = 6
	},self.Topbar)

	local controls = New("Frame",{
		AnchorPoint = Vector2.new(1,.5),
		Position = UDim2.new(1,-12,.5,0),
		Size = UDim2.fromOffset(37*5+5*4,38),
		BackgroundTransparency = 1,
		ZIndex = 8
	},self.Topbar)

	New("UIListLayout",{
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Right,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0,5)
	},controls)

	local function windowControl(icon,callback)
		local button = New("TextButton",{
			Size = UDim2.fromOffset(37,37),
			BackgroundColor3 = LiquidUI.Theme.Surface,
			BackgroundTransparency = .35,
			BorderSizePixel = 0,
			Text = "",
			AutoButtonColor = false,
			ZIndex = 9
		},controls)
		Corner(button,10)
		Stroke(button,.94,1)

		local iconObject = createIcon(button,icon,16,LiquidUI.Theme.SubText)
		if iconObject then
			iconObject.AnchorPoint = Vector2.new(.5,.5)
			iconObject.Position = UDim2.fromScale(.5,.5)
		end

		button.MouseEnter:Connect(function()
			Tween(button,{
				BackgroundColor3 = LiquidUI.Theme.SurfaceHover,
				BackgroundTransparency = 0
			})
			if iconObject then
				Tween(iconObject,{ImageColor3=LiquidUI.Theme.Text})
			end
		end)

		button.MouseLeave:Connect(function()
			Tween(button,{
				BackgroundColor3 = LiquidUI.Theme.Surface,
				BackgroundTransparency = .35
			})
			if iconObject then
				Tween(iconObject,{ImageColor3=LiquidUI.Theme.SubText})
			end
		end)

		button.MouseButton1Click:Connect(callback)
		return button
	end

	windowControl("lucide:settings",function()
		if self.SettingsCallback then
			task.spawn(self.SettingsCallback)
		end
	end)

	windowControl("lucide:minus",function()
		self:SetVisible(false)
	end)

	windowControl("lucide:panel-left",function()
		self:ToggleSidebar()
	end)

	windowControl("lucide:maximize-2",function()
		self:ToggleMaximize()
	end)

	windowControl("lucide:x",function()
		self:Destroy()
	end)

	-- Sidebar ----------------------------------------------------------

	self.Sidebar = New("Frame",{
		Name = "Sidebar",
		Position = UDim2.fromOffset(0,62),
		Size = UDim2.new(0,220,1,-62),
		BackgroundColor3 = LiquidUI.Theme.Sidebar,
		BackgroundTransparency = .06,
		BorderSizePixel = 0,
		ClipsDescendants = true,
		ZIndex = 4
	},self.Window)

	self.SearchHolder = New("Frame",{
		Position = UDim2.fromOffset(13,13),
		Size = UDim2.new(1,-26,0,39),
		BackgroundColor3 = LiquidUI.Theme.Surface,
		BackgroundTransparency = .08,
		BorderSizePixel = 0,
		ZIndex = 5
	},self.Sidebar)
	Corner(self.SearchHolder,11)
	Stroke(self.SearchHolder,.94,1)

	local searchIcon = createIcon(
		self.SearchHolder,
		"lucide:search",
		15,
		LiquidUI.Theme.Muted
	)
	if searchIcon then
		searchIcon.Position = UDim2.fromOffset(11,12)
	end

	self.Search = New("TextBox",{
		Position = UDim2.fromOffset(36,0),
		Size = UDim2.new(1,-43,1,0),
		BackgroundTransparency = 1,
		Text = "",
		PlaceholderText = config.SearchPlaceholder or "Search",
		PlaceholderColor3 = LiquidUI.Theme.Muted,
		TextColor3 = LiquidUI.Theme.Text,
		TextSize = 10,
		Font = Enum.Font.Gotham,
		ClearTextOnFocus = false,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 6
	},self.SearchHolder)

	self.Search:GetPropertyChangedSignal("Text"):Connect(function()
		self:FilterTabs(self.Search.Text)
	end)

	self.TabScroll = New("ScrollingFrame",{
		Position = UDim2.fromOffset(10,63),
		Size = UDim2.new(1,-20,1,-72),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 2,
		ScrollBarImageTransparency = .75,
		CanvasSize = UDim2.new(),
		ZIndex = 5
	},self.Sidebar)

	self.TabLayout = New("UIListLayout",{
		Padding = UDim.new(0,3),
		SortOrder = Enum.SortOrder.LayoutOrder
	},self.TabScroll)

	self.TabLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
		self.TabScroll.CanvasSize = UDim2.fromOffset(
			0,self.TabLayout.AbsoluteContentSize.Y+10
		)
	end)

	-- Content ------------------------------------------------------

	self.Content = New("Frame",{
		Name = "Content",
		Position = UDim2.fromOffset(220,62),
		Size = UDim2.new(1,-220,1,-62),
		BackgroundTransparency = 1,
		ZIndex = 3
	},self.Window)

	self.ContentScroll = New("ScrollingFrame",{
		Position = UDim2.fromOffset(25,21),
		Size = UDim2.new(1,-48,1,-37),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 3,
		ScrollBarImageTransparency = .72,
		CanvasSize = UDim2.new(),
		ZIndex = 4
	},self.Content)

	self.ContentLayout = New("UIListLayout",{
		Padding = UDim.new(0,12),
		SortOrder = Enum.SortOrder.LayoutOrder
	},self.ContentScroll)

	self.ContentLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
		self.ContentScroll.CanvasSize = UDim2.fromOffset(
			0,self.ContentLayout.AbsoluteContentSize.Y+25
		)
	end)

	self:SetupDrag()
	self:SetupResize()

	self.Connections.Toggle = UserInputService.InputBegan:Connect(function(input,processed)
		if processed then
			return
		end
		if input.KeyCode == self.ToggleKey then
			self:Toggle()
		end
	end)

	return self
end

function LiquidUI:SetupDrag()
	local dragging = false
	local dragStart
	local startPos

	self.Topbar.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			dragging = true
			dragStart = input.Position
			startPos = self.Container.Position
		end
	end)

	self.Topbar.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			dragging = false
		end
	end)

	self.Connections.Drag = UserInputService.InputChanged:Connect(function(input)
		if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
			local delta = input.Position-dragStart

			self.Container.Position = UDim2.new(
				startPos.X.Scale,startPos.X.Offset+delta.X,
				startPos.Y.Scale,startPos.Y.Offset+delta.Y
			)
		end
	end)
end

function LiquidUI:SetupResize()
	local handle = New("TextButton",{
		Name = "ResizeHandle",
		AnchorPoint = Vector2.new(1,1),
		Position = UDim2.fromScale(1,1),
		Size = UDim2.fromOffset(24,24),
		BackgroundTransparency = 1,
		Text = "",
		AutoButtonColor = false,
		ZIndex = 20
	},self.Window)

	local resizing = false
	local startMouse
	local startSize

	handle.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			resizing = true
			startMouse = input.Position
			startSize = self.Container.AbsoluteSize
		end
	end)

	handle.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			resizing = false
		end
	end)

	self.Connections.Resize = UserInputService.InputChanged:Connect(function(input)
		if resizing and input.UserInputType == Enum.UserInputType.MouseMovement then
			local delta = input.Position-startMouse

			local width = math.clamp(
				startSize.X+delta.X,
				self.MinSize.X,
				self.MaxSize.X
			)

			local height = math.clamp(
				startSize.Y+delta.Y,
				self.MinSize.Y,
				self.MaxSize.Y
			)

			self.Container.Size = UDim2.fromOffset(width,height)
		end
	end)
end

function LiquidUI:ToggleMaximize()
	if self.Maximized then
		self.Container.Size = self.PreviousSize
		self.Container.Position = self.PreviousPosition
		self.Maximized = false
		return
	end

	self.PreviousSize = self.Container.Size
	self.PreviousPosition = self.Container.Position

	self.Container.Position = UDim2.fromScale(.5,.5)
	self.Container.Size = UDim2.new(1,-50,1,-50)
	self.Maximized = true
end

function LiquidUI:ToggleSidebar()
	self.SidebarCollapsed = not self.SidebarCollapsed

	if self.SidebarCollapsed then
		Tween(self.Sidebar,{Size=UDim2.new(0,0,1,-62)},.18)
		Tween(self.Content,{
			Position = UDim2.fromOffset(0,62),
			Size = UDim2.new(1,0,1,-62)
		},.18)
	else
		Tween(self.Sidebar,{Size=UDim2.new(0,220,1,-62)},.18)
		Tween(self.Content,{
			Position = UDim2.fromOffset(220,62),
			Size = UDim2.new(1,-220,1,-62)
		},.18)
	end
end

function LiquidUI:SetVisible(value)
	self.Visible = value
	self.Container.Visible = value
end

function LiquidUI:Toggle()
	self:SetVisible(not self.Visible)
end

function LiquidUI:Open()
	self:SetVisible(true)
end

function LiquidUI:Close()
	self:SetVisible(false)
end

function LiquidUI:FilterTabs(query)
	query = string.lower(query or "")

	for _,tab in ipairs(self.Tabs) do
		local matches = query == "" or string.find(
			string.lower(tab.Name),
			query,
			1,
			true
		) ~= nil

		tab.Button.Visible = matches
	end
end

--// Rebuilds the sidebar's category headers + ordering. Tabs marked as
--// Favorite are pulled into their own section up top (mirrors the
--// reference design), everything else is grouped under its Category.
function LiquidUI:RebuildSidebar()
	for _,child in ipairs(self.TabScroll:GetChildren()) do
		if child.Name == "__SidebarHeader" then
			child:Destroy()
		end
	end

	local order = 0

	local function addHeader(text)
		order += 1
		New("TextLabel",{
			Name = "__SidebarHeader",
			Size = UDim2.new(1,0,0,22),
			BackgroundTransparency = 1,
			Text = string.upper(text),
			TextColor3 = LiquidUI.Theme.Muted,
			TextSize = 9,
			Font = Enum.Font.GothamBold,
			TextXAlignment = Enum.TextXAlignment.Left,
			LayoutOrder = order
		},self.TabScroll)
	end

	local favorites = {}
	local categories = {}
	local categoryOrder = {}

	for _,tab in ipairs(self.Tabs) do
		if tab.Favorite then
			table.insert(favorites,tab)
		else
			local cat = tab.Category or "General"
			if not categories[cat] then
				categories[cat] = {}
				table.insert(categoryOrder,cat)
			end
			table.insert(categories[cat],tab)
		end
	end

	if #favorites > 0 then
		addHeader("Favorite")
		for _,tab in ipairs(favorites) do
			order += 1
			tab.Button.LayoutOrder = order
		end
	end

	for _,cat in ipairs(categoryOrder) do
		addHeader(cat)
		for _,tab in ipairs(categories[cat]) do
			order += 1
			tab.Button.LayoutOrder = order
		end
	end
end

function LiquidUI:SelectTab(tab)
	if type(tab) == "string" then
		for _,candidate in ipairs(self.Tabs) do
			if candidate.Name == tab then
				tab = candidate
				break
			end
		end
	end

	if not tab then
		return
	end

	self.ActiveTab = tab

	for _,candidate in ipairs(self.Tabs) do
		local active = candidate == tab

		Tween(candidate.Button,{
			BackgroundColor3 = active
				and LiquidUI.Theme.SurfaceHover
				or LiquidUI.Theme.Surface,
			BackgroundTransparency = active and .05 or 1
		})

		if candidate.IconObject then
			Tween(candidate.IconObject,{
				ImageColor3 = active
					and LiquidUI.Theme.AccentBright
					or LiquidUI.Theme.SubText
			})
		end

		Tween(candidate.Label,{
			TextColor3 = active
				and LiquidUI.Theme.Text
				or LiquidUI.Theme.SubText
		})
	end

	for _,child in ipairs(self.ContentScroll:GetChildren()) do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end

	tab:Render()
end

function LiquidUI:CreateTab(config)
	config = config or {}

	-- IMPORTANT: the metatable is attached immediately, not at the end of
	-- this function, so tab:Render() (called by SelectTab below, for the
	-- very first tab) is guaranteed to exist. This is what the
	-- "attempt to call missing method 'Render'" error was caused by.
	local tab = setmetatable({},{__index=LiquidUI.Tab})

	tab.Window = self
	tab.Name = config.Name or "Tab"
	tab.Icon = config.Icon
	tab.Description = config.Description or ""
	tab.Category = config.Category or "General"
	tab.Favorite = config.Favorite == true
	tab.Elements = {}

	local button = New("TextButton",{
		Size = UDim2.new(1,0,0,38),
		BackgroundColor3 = LiquidUI.Theme.Surface,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Text = "",
		AutoButtonColor = false,
		ZIndex = 6
	},self.TabScroll)
	Corner(button,10)

	local icon = createIcon(
		button,
		tab.Icon,
		16,
		LiquidUI.Theme.SubText
	)

	if icon then
		icon.Position = UDim2.fromOffset(11,11)
	end

	local label = New("TextLabel",{
		Position = UDim2.fromOffset(icon and 37 or 13,0),
		Size = UDim2.new(1,-70,1,0),
		BackgroundTransparency = 1,
		Text = tab.Name,
		TextColor3 = LiquidUI.Theme.SubText,
		TextSize = 11,
		Font = Enum.Font.GothamMedium,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
		ZIndex = 7
	},button)

	-- Favorite star toggle. This is its own TextButton so clicking it
	-- doesn't also trigger the tab-select click behind it.
	local star = New("TextButton",{
		AnchorPoint = Vector2.new(1,.5),
		Position = UDim2.new(1,-9,.5,0),
		Size = UDim2.fromOffset(20,20),
		BackgroundTransparency = 1,
		Text = "",
		AutoButtonColor = false,
		ZIndex = 8
	},button)

	local starIcon = createIcon(
		star,
		"lucide:star",
		14,
		tab.Favorite and LiquidUI.Theme.Yellow or LiquidUI.Theme.Muted
	)
	if starIcon then
		starIcon.AnchorPoint = Vector2.new(.5,.5)
		starIcon.Position = UDim2.fromScale(.5,.5)
	end

	star.MouseButton1Click:Connect(function()
		tab.Favorite = not tab.Favorite
		if starIcon then
			Tween(starIcon,{
				ImageColor3 = tab.Favorite
					and LiquidUI.Theme.Yellow
					or LiquidUI.Theme.Muted
			},.12)
		end
		self:RebuildSidebar()
	end)

	button.MouseEnter:Connect(function()
		if self.ActiveTab ~= tab then
			Tween(button,{
				BackgroundColor3 = LiquidUI.Theme.SurfaceHover,
				BackgroundTransparency = .72
			})
			Tween(label,{TextColor3=LiquidUI.Theme.Text})
			if icon then
				Tween(icon,{ImageColor3=LiquidUI.Theme.Text})
			end
		end
	end)

	button.MouseLeave:Connect(function()
		if self.ActiveTab ~= tab then
			Tween(button,{BackgroundTransparency=1})
			Tween(label,{TextColor3=LiquidUI.Theme.SubText})
			if icon then
				Tween(icon,{ImageColor3=LiquidUI.Theme.SubText})
			end
		end
	end)

	button.MouseButton1Click:Connect(function()
		self:SelectTab(tab)
	end)

	tab.Button = button
	tab.IconObject = icon
	tab.Label = label
	tab.StarButton = star
	tab.StarIcon = starIcon

	table.insert(self.Tabs,tab)
	self:RebuildSidebar()

	if not self.ActiveTab then
		self:SelectTab(tab)
	end

	return tab
end

--// ---------------------------------------------------------------------
--// Tab / element builders
--// ---------------------------------------------------------------------

LiquidUI.Tab = {}

function LiquidUI.Tab:Render()
	local window = self.Window

	New("TextLabel",{
		Size = UDim2.new(1,-5,0,27),
		BackgroundTransparency = 1,
		Text = self.Name,
		TextColor3 = LiquidUI.Theme.Text,
		TextSize = 18,
		Font = Enum.Font.GothamBold,
		TextXAlignment = Enum.TextXAlignment.Left,
		LayoutOrder = -100
	},window.ContentScroll)

	if self.Description ~= "" then
		New("TextLabel",{
			Size = UDim2.new(1,-5,0,17),
			BackgroundTransparency = 1,
			Text = self.Description,
			TextColor3 = LiquidUI.Theme.SubText,
			TextSize = 10,
			Font = Enum.Font.Gotham,
			TextXAlignment = Enum.TextXAlignment.Left,
			LayoutOrder = -99
		},window.ContentScroll)
	end

	for _,builder in ipairs(self.Elements) do
		builder()
	end
end

function LiquidUI.Tab:SetDescription(text)
	self.Description = text or ""
	if self.Window.ActiveTab == self then
		self.Window:SelectTab(self)
	end
	return self
end

function LiquidUI.Tab:SetFavorite(value)
	self.Favorite = value == true
	if self.StarIcon then
		self.StarIcon.ImageColor3 = self.Favorite
			and LiquidUI.Theme.Yellow
			or LiquidUI.Theme.Muted
	end
	self.Window:RebuildSidebar()
	return self
end

function LiquidUI.Tab:CreateSection(text)
	table.insert(self.Elements,function()
		New("TextLabel",{
			Size = UDim2.new(1,-5,0,18),
			BackgroundTransparency = 1,
			Text = string.upper(text or "SECTION"),
			TextColor3 = LiquidUI.Theme.Muted,
			TextSize = 9,
			Font = Enum.Font.GothamBold,
			TextXAlignment = Enum.TextXAlignment.Left
		},self.Window.ContentScroll)
	end)
	return self
end

function LiquidUI.Tab:CreateButton(config)
	config = config or {}

	table.insert(self.Elements,function()
		local button = New("TextButton",{
			Size = UDim2.new(1,-5,0,45),
			BackgroundColor3 = LiquidUI.Theme.Surface,
			BackgroundTransparency = .04,
			BorderSizePixel = 0,
			Text = "",
			AutoButtonColor = false
		},self.Window.ContentScroll)
		Corner(button,11)
		Stroke(button,.93,1)

		local icon = createIcon(
			button,
			config.Icon,
			18,
			config.Color or LiquidUI.Theme.AccentBright
		)

		if icon then
			icon.Position = UDim2.fromOffset(13,13)
		end

		New("TextLabel",{
			Position = UDim2.fromOffset(icon and 43 or 14,0),
			Size = UDim2.new(1,-85,1,0),
			BackgroundTransparency = 1,
			Text = config.Name or "Button",
			TextColor3 = config.Color or LiquidUI.Theme.Text,
			TextSize = 11,
			Font = Enum.Font.GothamBold,
			TextXAlignment = Enum.TextXAlignment.Left
		},button)

		if config.Key then
			New("TextLabel",{
				AnchorPoint = Vector2.new(1,.5),
				Position = UDim2.new(1,-13,.5,0),
				Size = UDim2.fromOffset(38,21),
				BackgroundColor3 = LiquidUI.Theme.Background,
				BackgroundTransparency = .2,
				Text = tostring(config.Key),
				TextColor3 = LiquidUI.Theme.Muted,
				TextSize = 8,
				Font = Enum.Font.GothamMedium
			},button)
		end

		button.MouseEnter:Connect(function()
			Tween(button,{BackgroundColor3=LiquidUI.Theme.SurfaceHover})
		end)

		button.MouseLeave:Connect(function()
			Tween(button,{BackgroundColor3=LiquidUI.Theme.Surface})
		end)

		button.MouseButton1Click:Connect(function()
			if config.Callback then
				task.spawn(config.Callback)
			end
		end)
	end)

	return self
end

--// A row of compact "quick access" buttons that evenly split the
--// available width -- this is the {icon, colored bold text, KEY pill}
--// style used for grouped actions (Kill / Heal / Explode / Fling, etc).
--// Pass a single item to get a full-width button (like "RoSandbox Tools").
--//
--//   tab:CreateButtonRow({
--//       {Name="Kill", Icon="lucide:skull", Color=Theme.Red, Key="K", Callback=...},
--//       {Name="Heal", Icon="lucide:heart-pulse", Color=Theme.Green, Key="H", Callback=...},
--//   })
function LiquidUI.Tab:CreateButtonRow(items)
	items = items or {}
	if #items == 0 then
		return self
	end

	table.insert(self.Elements,function()
		local gap = 10
		local count = #items

		local row = New("Frame",{
			Size = UDim2.new(1,-5,0,52),
			BackgroundTransparency = 1
		},self.Window.ContentScroll)

		New("UIListLayout",{
			FillDirection = Enum.FillDirection.Horizontal,
			Padding = UDim.new(0,gap),
			SortOrder = Enum.SortOrder.LayoutOrder
		},row)

		for index,item in ipairs(items) do
			local cellWidth = (1/count)
			local cellOffset = -(gap*(count-1)/count)

			local button = New("TextButton",{
				Size = UDim2.new(cellWidth,cellOffset,1,0),
				BackgroundColor3 = LiquidUI.Theme.Surface,
				BackgroundTransparency = .04,
				BorderSizePixel = 0,
				Text = "",
				AutoButtonColor = false,
				LayoutOrder = index
			},row)
			Corner(button,11)
			Stroke(button,.93,1)

			local color = item.Color or LiquidUI.Theme.AccentBright

			local iconHolder = New("Frame",{
				Position = UDim2.fromOffset(11,11),
				Size = UDim2.fromOffset(30,30),
				BackgroundColor3 = color,
				BackgroundTransparency = .84,
				BorderSizePixel = 0
			},button)
			Corner(iconHolder,9)

			local icon = createIcon(iconHolder,item.Icon,16,color)
			if icon then
				icon.AnchorPoint = Vector2.new(.5,.5)
				icon.Position = UDim2.fromScale(.5,.5)
			end

			New("TextLabel",{
				Position = UDim2.fromOffset(49,0),
				Size = UDim2.new(1,item.Key and -85 or -58,1,0),
				BackgroundTransparency = 1,
				Text = item.Name or "Action",
				TextColor3 = color,
				TextSize = 11,
				Font = Enum.Font.GothamBold,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextTruncate = Enum.TextTruncate.AtEnd
			},button)

			if item.Key then
				New("TextLabel",{
					AnchorPoint = Vector2.new(1,.5),
					Position = UDim2.new(1,-11,.5,0),
					Size = UDim2.fromOffset(34,20),
					BackgroundColor3 = LiquidUI.Theme.Background,
					BackgroundTransparency = .2,
					Text = tostring(item.Key),
					TextColor3 = LiquidUI.Theme.Muted,
					TextSize = 8,
					Font = Enum.Font.GothamMedium
				},button)
			end

			button.MouseEnter:Connect(function()
				Tween(button,{BackgroundColor3=LiquidUI.Theme.SurfaceHover})
			end)

			button.MouseLeave:Connect(function()
				Tween(button,{BackgroundColor3=LiquidUI.Theme.Surface})
			end)

			button.MouseButton1Click:Connect(function()
				if item.Callback then
					task.spawn(item.Callback)
				end
			end)
		end
	end)

	return self
end

function LiquidUI.Tab:CreateToggle(config)
	config = config or {}
	local state = config.Default == true

	table.insert(self.Elements,function()
		local holder = New("Frame",{
			Size = UDim2.new(1,-5,0,51),
			BackgroundColor3 = LiquidUI.Theme.Surface,
			BackgroundTransparency = .04,
			BorderSizePixel = 0
		},self.Window.ContentScroll)
		Corner(holder,11)
		Stroke(holder,.93,1)

		New("TextLabel",{
			Position = UDim2.fromOffset(14,0),
			Size = UDim2.new(1,-85,1,0),
			BackgroundTransparency = 1,
			Text = config.Name or "Toggle",
			TextColor3 = LiquidUI.Theme.Text,
			TextSize = 11,
			Font = Enum.Font.GothamMedium,
			TextXAlignment = Enum.TextXAlignment.Left
		},holder)

		local toggle = New("TextButton",{
			AnchorPoint = Vector2.new(1,.5),
			Position = UDim2.new(1,-13,.5,0),
			Size = UDim2.fromOffset(44,24),
			BackgroundColor3 = Color3.fromRGB(55,57,65),
			BorderSizePixel = 0,
			Text = "",
			AutoButtonColor = false
		},holder)
		Corner(toggle,100)

		local knob = New("Frame",{
			Position = UDim2.fromOffset(4,4),
			Size = UDim2.fromOffset(16,16),
			BackgroundColor3 = LiquidUI.Theme.Muted,
			BorderSizePixel = 0
		},toggle)
		Corner(knob,100)

		local function update()
			Tween(toggle,{
				BackgroundColor3 = state
					and LiquidUI.Theme.Accent
					or Color3.fromRGB(55,57,65)
			})

			Tween(knob,{
				Position = state
					and UDim2.new(1,-20,0,4)
					or UDim2.fromOffset(4,4),
				BackgroundColor3 = state
					and LiquidUI.Theme.White
					or LiquidUI.Theme.Muted
			})
		end

		update()

		toggle.MouseButton1Click:Connect(function()
			state = not state
			update()
			if config.Callback then
				task.spawn(config.Callback,state)
			end
		end)
	end)

	return self
end

function LiquidUI.Tab:CreateSlider(config)
	config = config or {}

	local minimum = config.Min or 0
	local maximum = config.Max or 100
	local value = math.clamp(config.Default or minimum,minimum,maximum)

	table.insert(self.Elements,function()
		local holder = New("Frame",{
			Size = UDim2.new(1,-5,0,68),
			BackgroundColor3 = LiquidUI.Theme.Surface,
			BackgroundTransparency = .04,
			BorderSizePixel = 0
		},self.Window.ContentScroll)
		Corner(holder,11)
		Stroke(holder,.93,1)

		New("TextLabel",{
			Position = UDim2.fromOffset(14,8),
			Size = UDim2.new(1,-100,0,20),
			BackgroundTransparency = 1,
			Text = config.Name or "Slider",
			TextColor3 = LiquidUI.Theme.Text,
			TextSize = 11,
			Font = Enum.Font.GothamMedium,
			TextXAlignment = Enum.TextXAlignment.Left
		},holder)

		local valueLabel = New("TextLabel",{
			AnchorPoint = Vector2.new(1,0),
			Position = UDim2.new(1,-14,0,8),
			Size = UDim2.fromOffset(70,20),
			BackgroundTransparency = 1,
			Text = tostring(value),
			TextColor3 = LiquidUI.Theme.AccentBright,
			TextSize = 10,
			Font = Enum.Font.GothamBold,
			TextXAlignment = Enum.TextXAlignment.Right
		},holder)

		local bar = New("Frame",{
			Position = UDim2.fromOffset(14,43),
			Size = UDim2.new(1,-28,0,5),
			BackgroundColor3 = Color3.fromRGB(52,54,62),
			BorderSizePixel = 0
		},holder)
		Corner(bar,100)

		local fill = New("Frame",{
			Size = UDim2.new((value-minimum)/(maximum-minimum),0,1,0),
			BackgroundColor3 = LiquidUI.Theme.Accent,
			BorderSizePixel = 0
		},bar)
		Corner(fill,100)

		local knob = New("Frame",{
			AnchorPoint = Vector2.new(.5,.5),
			Position = UDim2.new((value-minimum)/(maximum-minimum),0,.5,0),
			Size = UDim2.fromOffset(14,14),
			BackgroundColor3 = LiquidUI.Theme.White,
			BorderSizePixel = 0
		},bar)
		Corner(knob,100)

		local dragging = false

		local function update(x)
			local percentage = math.clamp(
				(x-bar.AbsolutePosition.X)/bar.AbsoluteSize.X,
				0,1
			)

			local newValue = minimum+(maximum-minimum)*percentage

			if config.Rounding ~= false then
				newValue = math.floor(newValue+.5)
			end

			value = newValue
			fill.Size = UDim2.new(percentage,0,1,0)
			knob.Position = UDim2.new(percentage,0,.5,0)
			valueLabel.Text = tostring(newValue)

			if config.Callback then
				task.spawn(config.Callback,newValue)
			end
		end

		bar.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 then
				dragging = true
				update(input.Position.X)
			end
		end)

		UserInputService.InputChanged:Connect(function(input)
			if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
				update(input.Position.X)
			end
		end)

		UserInputService.InputEnded:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 then
				dragging = false
			end
		end)
	end)

	return self
end

function LiquidUI.Tab:CreateInput(config)
	config = config or {}

	table.insert(self.Elements,function()
		local holder = New("Frame",{
			Size = UDim2.new(1,-5,0,47),
			BackgroundColor3 = LiquidUI.Theme.Surface,
			BackgroundTransparency = .04,
			BorderSizePixel = 0
		},self.Window.ContentScroll)
		Corner(holder,11)
		Stroke(holder,.93,1)

		if config.Name then
			New("TextLabel",{
				Position = UDim2.fromOffset(13,0),
				Size = UDim2.fromOffset(110,47),
				BackgroundTransparency = 1,
				Text = config.Name,
				TextColor3 = LiquidUI.Theme.SubText,
				TextSize = 10,
				Font = Enum.Font.GothamMedium,
				TextXAlignment = Enum.TextXAlignment.Left
			},holder)
		end

		local input = New("TextBox",{
			Position = UDim2.fromOffset(config.Name and 120 or 13,0),
			Size = UDim2.new(1,config.Name and -133 or -26,1,0),
			BackgroundTransparency = 1,
			Text = config.Default or "",
			PlaceholderText = config.Placeholder or "Enter text...",
			PlaceholderColor3 = LiquidUI.Theme.Muted,
			TextColor3 = LiquidUI.Theme.Text,
			TextSize = 10,
			Font = Enum.Font.Gotham,
			ClearTextOnFocus = false,
			TextXAlignment = Enum.TextXAlignment.Right
		},holder)

		input.FocusLost:Connect(function(enter)
			if config.Callback then
				task.spawn(config.Callback,input.Text,enter)
			end
		end)
	end)

	return self
end

function LiquidUI.Tab:CreateLabel(text)
	table.insert(self.Elements,function()
		New("TextLabel",{
			Size = UDim2.new(1,-5,0,24),
			BackgroundTransparency = 1,
			Text = text or "",
			TextColor3 = LiquidUI.Theme.SubText,
			TextSize = 10,
			Font = Enum.Font.Gotham,
			TextXAlignment = Enum.TextXAlignment.Left
		},self.Window.ContentScroll)
	end)
	return self
end

function LiquidUI.Tab:CreateDivider()
	table.insert(self.Elements,function()
		New("Frame",{
			Size = UDim2.new(1,-5,0,1),
			BackgroundColor3 = LiquidUI.Theme.White,
			BackgroundTransparency = .93,
			BorderSizePixel = 0
		},self.Window.ContentScroll)
	end)
	return self
end

function LiquidUI:Destroy()
	self.Destroyed = true

	for _,connection in pairs(self.Connections) do
		pcall(function()
			connection:Disconnect()
		end)
	end

	if self.Gui then
		self.Gui:Destroy()
	end
end

return LiquidUI
