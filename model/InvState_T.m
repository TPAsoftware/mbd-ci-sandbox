classdef InvState_T < Simulink.IntEnumType
    %INVSTATE_T  Operating state of the inverter (output InvState of InvStateMachine).

    enumeration
        OFF(0)
        STANDBY(1)
        PRECHARGE(2)
        READY(3)
        RUN(4)
        SAFE_DISCHARGE(5)
        FAULT(6)
    end

    methods (Static)
        function v = getDefaultValue()
            v = InvState_T.OFF;
        end

        function d = getDescription()
            d = 'Inverter operating state';
        end

        function b = addClassNameToEnumNames()
            b = true;
        end
    end
end
