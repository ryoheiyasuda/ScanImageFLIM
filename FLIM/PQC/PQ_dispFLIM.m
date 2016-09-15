function PQ_dispFLIM(calculateLifetime, focus)
global spc state gh gui

if ~nargin
    calculateLifetime = 1;
end

res = state.spc.acq.SPCdata.adc_resolution;
range = [1, res];
resolution = state.spc.acq.resolution; %ps
    
siz = size(spc.stack.stackF);

factor = 1; %pixel value / photon

% if ~state.spc.acq.spc_average
%     factor = 1;
% else
%     if focus
%         factor = state.acq.numberOfFrames/(state.internal.frameCounter+1);
%     else
%         factor = state.acq.numberOfFrames;
%     end
% end

if ~calculateLifetime
    if focus
        frame = spc.stack.stackF(:,:,:,1);
    elseif ~state.spc.acq.spc_average
        frame = spc.stack.stackF(:,:,:,state.internal.frameCounter+1);
    else
        %frame = spc.stack.stackF(:,:,:,state.internal.frameCounter+1);
        frame = sum(spc.stack.stackF(:,:,:,1:state.internal.frameCounter+1), 4);
    end
    sum_projection = reshape(sum(frame, 1), siz(2), siz(3));
    
    if state.spc.acq.SPCdata.n_channels > 1
        y1 = state.acq.linesPerFrame*(gui.spc.proChannel-1) + 1: state.acq.linesPerFrame*gui.spc.proChannel;
        image1 = sum_projection(y1, :);
    end
    
   % set(gui.spc.figure.projectImage, 'CData', image1*factor);
    %drawnow;
else
    if state.spc.acq.spc_average || focus
       sum_Frame = sum(spc.stack.stackF, 4);
    else
       %fprintf('%d\n', state.internal.frameCounter);
       sum_Frame = spc.stack.stackF(:,:,:,state.internal.frameCounter+1);  
    end
    
    if focus
        sum_Frame = sum_Frame*factor;
    end
    
    spc.stack.image1 = {};
    spc.stack.project = [];
    
    scan_size_x = state.acq.pixelsPerLine;
    scan_size_y = state.acq.linesPerFrame;
    image1 = sum_Frame;
    
    %figure; imagesc(sum_projection);
    spc.lifetime= sum(sum(image1, 2),3);
    spc.switches.imagemode = 1;
    spc.switches.logscale = 1;
    for i = 1:state.spc.acq.SPCdata.n_channels
        spc.fit(i).range = range;
    end;
    
    spc.datainfo.time = datestr(clock, 13);
    spc.datainfo.date = datestr(clock, 1);

    spc.datainfo.scan_x = scan_size_x;
    spc.datainfo.scan_y = scan_size_y*state.spc.acq.SPCdata.n_channels;
    spc.datainfo.pix_time = state.acq.pixelTime;
    spc.datainfo.adc_re = res;
    spc.datainfo.pulseInt= 1e9/double(spc.datainfo.pulseRate);
    %spc.datainfo.pulseInt = 12.1; %double(pulseInt);
    
    spc.SPCdata.line_compression = 1;
    spc.SPCdata.scan_size_x = scan_size_x;
    spc.SPCdata.scan_size_y = scan_size_y;
    spc.SPCdata.scan_rout_x = state.spc.acq.SPCdata.n_channels;
    spc.switches.noSPC = 0;
    spc.switches.redImg = 0;
    
    try
        spc.datainfo.triggerTime = state.spc.acq.triggerTime;
    catch
        warning('Trigger time is not set');
        spc.datainfo.triggerTime = datestr(now);
    end
    
    spc.datainfo.psPerUnit = resolution;
    spc.size = size(image1);
    spc.imageMod = image1;
    %z = state.internal.zSliceCounter
    if state.internal.zSliceCounter == 0 || state.internal.usePage || ~state.spc.acq.spc_average %Frame
        spc.stack.image1{1} = spc.imageMod;
        set(gui.spc.spc_main.spc_page, 'String', '1')
    else
        spc.stack.image1{state.internal.zSliceCounter} = spc.imageMod;
        set(gui.spc.spc_main.spc_page, 'String', num2str(1:state.internal.zSliceCounter))
    end
    
    %set(gui.spc.figure.LutLowerlimit, 'String', '0');
    if state.files.fileCounter == 1
        set(gui.spc.figure.projectAuto, 'value', 1)
    end
    try
        spc_redrawSetting(1); %Calculate spc.stack.project too.
        spc_redrawSetting(1);
    end
end