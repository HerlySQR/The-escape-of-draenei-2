OnInit("MotionSensor", function ()
    Require "LinkedList" -- https://www.hiveworkshop.com/threads/definitive-doubly-linked-list.339392/
    Require "Event" -- https://www.hiveworkshop.com/threads/event-gui-friendly.339451/
    Require "Set" -- https://www.hiveworkshop.com/threads/set-group-datastructure.331886/
    Require "Timed" -- https://www.hiveworkshop.com/threads/timed-call-and-echo.339222/
    Require "AddHook"  -- https://www.hiveworkshop.com/threads/hook-v5-0-1.339153/

    --[[
        System based on MotionSensor v1.4.0 by AGD -- https://www.hiveworkshop.com/threads/system-motion-sensor.287219/

        This simple system allows you to check if the current motion
        a unit is stationary or in motion (This includes triggered
        motion). You can also use this to get the instantaneous speed
        of a unit and its direction of motion. This also allows you to
        detect a change in motion event i.e. when either a unit in
        motion stops or a stationary unit moves. Furthermore, the system
        includes many other utilities regarding unit motion.
    ]]

    --=========================== Configuration ===========================

    --[[
        Unit position check interval (Values greater than 0.03
        causes a bit of inaccuracy in the given instantaneous
        speed of a unit. As the value lowers, the accuracy
        increases at the cost of performance.)
    ]]
    local PERIOD = 0.03

    --[[
        Set to true if you want the system to automatically
        register units upon entering the map. Set to false if
        you want to manually register units.
    ]]
    local AUTO_REGISTER_UNITS = true

    --======================= End of Configuration ========================
    --   Do not change anything below this line if you're not so sure on   
    --                         what you're doing.                          
    --=====================================================================


    ---@class MotionSensor : LinkedList
    ---@field public main unit                     The sensored unit
    ---@field public moving boolean                Checks if it is moving or not
    ---@field public speed number                  The instantaneous speed
    ---@field public direction number              The direction of motion
    ---@field public deltaX number                 X component of the instantaneous speed
    ---@field public deltaY number                 Y component of the instantaneous speed
    ---@field public prevX number                  The previous x-coordinate
    ---@field public prevY number                  The previous y-coordinate
    ---@field public motionState MotionState       The current motion state of the motion changing unit
    MotionSensor = LinkedList.create()

    local runStart, runStop, runChange

    ---Registers a callback to run when a stationary unit moves.
    ---
    ---To unregister call the `remove()` method of the returned value.
    MotionSensor.startEvent, runStart = Event.create()

    ---Registers a callback to run when a unit stops moving.
    ---
    ---To unregister call the `remove()` method of the returned value.
    MotionSensor.stopEvent, runStop = Event.create()

    ---Registers a callback to run during a motion change event.
    ---
    ---To unregister call the `remove()` method of the returned value.
    MotionSensor.changeEvent, runChange = Event.create()

    ---@class MotionState
    MOTION_STATE_MOVING        = 1 ---@type MotionState
    MOTION_STATE_STATIONARY    = 2 ---@type MotionState

    SENSOR_GROUP_MOVING        = Set.create()
    SENSOR_GROUP_STATIONARY    = Set.create()

    local enabled ---@type boolean
    local staticTimer ---@type function

    local function OnPeriodic()
        for node in MotionSensor:loop() do
            local sensor = node.value
            local u = sensor.main
            local prevState = sensor.moving
            local unitX, unitY = GetUnitX(u), GetUnitY(u)
            local dx, dy = unitX - sensor.prevX, unitY - sensor.prevY
            sensor.prevX, sensor.prevY = unitX, unitY
            sensor.deltaX, sensor.deltaY = dx, dy
            sensor.speed = math.sqrt(dx^2 + dy^2) / PERIOD
            sensor.direction = math.atan(dy, dx)
            sensor.moving = sensor.speed > 0.

            if prevState ~= sensor.moving then
                if sensor.moving then
                    SENSOR_GROUP_STATIONARY:removeSingle(u)
                    SENSOR_GROUP_MOVING:addSingle(u)
                    sensor.motionState = MOTION_STATE_MOVING
                    runStart(sensor)
                else
                    SENSOR_GROUP_MOVING:removeSingle(u)
                    SENSOR_GROUP_STATIONARY:addSingle(u)
                    sensor.motionState = MOTION_STATE_STATIONARY
                    runStop(sensor)
                end
                runChange(sensor)
            end
        end
    end

    ---Registers a unit to the system if is not registered
    ---@param u unit
    function MotionSensor.addUnit(u)
        if not u then
            error("Attempt to register a nil unit", 2)
        end
        if MotionSensor[u] then
            return
        end
        local self = {} ---@type MotionSensor

        self.main = u
        MotionSensor[u] = self

        -- Enable the Sensor iterator again when this is the first instance to be added on the list
        if enabled and MotionSensor.n == 0 then
            staticTimer = Timed.echo(OnPeriodic, PERIOD)
        end

        MotionSensor:insert(self)

        self.motionState = MOTION_STATE_STATIONARY
        SENSOR_GROUP_STATIONARY:addSingle(u)
        -- Initialize prevX and prevY for the newly registered unit to prevent it from causing a motion change event false positive

        self.prevX, self.prevY = GetUnitX(u), GetUnitY(u)
    end

    ---Unregisters a unit to the system if is registered
    ---@param u unit
    function MotionSensor.removeUnit(u)
        if not u then
            error("Attempt to unregister a nil unit", 2)
        end
        local self = MotionSensor[u]
        if not self then
            return
        end
        MotionSensor:remove(self)
        MotionSensor[u] = nil
        if SENSOR_GROUP_MOVING:contains(u) then
            SENSOR_GROUP_MOVING:remove(u)
        else
            SENSOR_GROUP_STATIONARY:remove(u)
        end
        -- If the list is empty, stop iterating
        if enabled and MotionSensor.n == 0 then
            staticTimer()
        end
    end

    ---Returns a Sensor instance based on the unit parameter
    ---@param u unit
    ---@return MotionSensor
    function MotionSensor.get(u)
        return MotionSensor[u]
    end

    ---Enables/Disables the Motion Sensor
    ---@param flag boolean
    function MotionSensor.setEnabled(flag)
        enabled = flag
        if flag then
            if MotionSensor.n > 0 then
                staticTimer = Timed.echo(OnPeriodic, PERIOD)
            else
                staticTimer()
            end
        end
    end

    ---@return boolean
    function MotionSensor.isEnabled()
        return enabled
    end

    if AUTO_REGISTER_UNITS then
        local oldFunc
        oldFunc = AddHook("CreateUnit", function (...)
            local u = oldFunc(...)
            if u then
                MotionSensor.addUnit(u)
            end
            return u
        end)
    end
    local oldFunc
    oldFunc = AddHook("RemoveUnit", function (u)
        if u then
            MotionSensor.removeUnit(u)
        end
        oldFunc(u)
    end)
    -- Turn on Sensor
    enabled = true

end)