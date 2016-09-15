function PQC_acqTimerFcn(focus)
global spc gh

if focus
    h = gh.mainControls.focusButton;
    val=get(h, 'String');
else
    h = gh.mainControls.grabOneButton;
    val=get(h, 'String');
end

if ~strcmp(val, 'ABORT')
    pause(0.1);
    return;
else
    pause(0.001);
end

if spc.datainfo.pulseRate <= 1e2
    fprintf('###PQC_acqTimerFcn ###\n');
    fprintf('Laser pulse not detected!!!\n');
    fprintf('Check imaging laser!!!\n');
    fprintf('###PQC_acqTimerFcn ###\n');
    if focus
        if strcmp(val, 'ABORT')
            executeFocusCallback(h);
        end
        
    else
        if strcmp(val, 'ABORT')
            executeGrabOneCallback(h);
        end
    end
    return;
end

if ~strcmp(val, 'ABORT')
    return;
end

for i = 1:10
    if focus
        [ret, nLines, acqLines] = PQC_makeStripe;
    else
        [ret, nLines, acqLines] = PQC_makeFrameByStripes;
    end
    
    if ret < 0
        fprintf('###PQC_acqTimerFcn ###\n');
        fprintf('ERROR DURING IMAGE ACQ!!!\n');
        fprintf('###PQC_acqTimerFcn ###\n');
        if focus
            if strcmp(val, 'ABORT')
                executeFocusCallback(h);
            end
            
        else
            if strcmp(val, 'ABORT')
                executeGrabOneCallback(h);
            end
        end
        
    end
     
    if nLines == acqLines
        break;
    else
       %disp([nLines, acqLines]);
    end
end