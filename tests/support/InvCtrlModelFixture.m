classdef InvCtrlModelFixture < matlab.unittest.fixtures.Fixture
    %INVCTRLMODELFIXTURE  Shared fixture: build InvCtrl once for the whole test run.
    %
    %   The model is generated from model/build_inv_ctrl.m, so every test run
    %   tests exactly the scripted definition that is under version control.

    properties (Constant)
        ModelName = 'InvCtrl'
    end

    methods
        function setup(fixture)
            fixture.SetupDescription = 'Build InvCtrl from model/build_inv_ctrl.m';
            fixture.TeardownDescription = 'Close InvCtrl';
            inv_ctrl_setup();
            build_inv_ctrl();
        end

        function teardown(fixture)
            if bdIsLoaded(fixture.ModelName)
                close_system(fixture.ModelName, 0);
            end
        end
    end
end
