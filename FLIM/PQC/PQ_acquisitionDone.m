function PQ_acquisitionDone
global state spc

state.spc.internal.hPQ.stopMeas;

final = (state.internal.zSliceCounter > 0) ...
    && state.internal.zSliceCounter == state.acq.numberOfZSlices;

if final
    PQ_dispFLIM(1, 0); %0.13 s.
    
    fileCounter = state.files.fileCounter;
    if ~state.spc.acq.spc_average
        
%         state.files.fileCounter = fileCounter - 1;
%         updateFullFileName(0);
        FLIM_saveFrameScanning;
        
    elseif state.internal.usePage
        spc.stack.stackA(:,:,:,state.internal.zSliceCounter) = sum(spc.stack.stackF, 4);
        binPage = floor(state.acq.numberOfZSlices/state.acq.numberOfBinPages);
        for i = 1:binPage
            pageStart = (i-1)*state.acq.numberOfBinPages + 1;
            pageEnd = i*state.acq.numberOfBinPages;
            %disp([pageStart, pageEnd]);
            spc.stack.stackF = spc.stack.stackA(:, :, :, pageStart:pageEnd);
            PQ_dispFLIM(1, 0);
            pause(0.01);
            state.files.fileCounter = fileCounter -2 + i;
            updateFullFileName(0);
            state.internal.triggerTimeString = state.spc.internal.triggerTimeArray{pageStart};
            spc.datainfo.triggerTime = state.spc.internal.triggerTimeArray{pageStart};
            display(spc.datainfo.triggerTime);
            spc_updateTriggerTime;
            updateGUIByGlobal('state.files.fileCounter');
            spc_writeData(0); %0.23 s.
%             spc.stack.project = spc.stack.project / state.acq.numberOfBinPages;
            PQ_saveRegularData;
            pause(0.01);
            try
                spc_auto(0);
            end
        end
        
    else
%         state.files.fileCounter = fileCounter - 1;
%         updateFullFileName(0);
        spc_writeData(0);
        PQ_saveRegularData;
        spc_maxProc_offLine;
        try
            spc_auto(0);
        end
    end
    
    state.files.fileCounter = state.files.fileCounter + 1;
    updateFullFileName(0);
    updateGUIByGlobal('state.files.fileCounter');
    
else %taking slices.
    if state.internal.usePage
        closeShutter;
        binPage = floor((state.internal.zSliceCounter)/state.acq.numberOfBinPages);
        spc.stack.stackA(:,:,:,state.internal.zSliceCounter) = sum(spc.stack.stackF, 4);
        
        if sum(state.yphys.acq.uncagePage == state.internal.zSliceCounter) && isempty(state.yphys.acq.frame_scanning) && state.spc.acq.uncageBox
            yphys_uncage(1);
            uncaged = 1;
            flushAOData;
        else
            uncaged = 0;
        end
        
        
        %Timing
        tocData = toc(state.internal.pageTicID);
        state.spc.acq.timing(state.internal.zSliceCounter+1+state.spc.internal.frameDone) = tocData;
        waitT = state.acq.pageInterval - (tocData - state.spc.acq.timing(state.internal.zSliceCounter+state.spc.internal.frameDone));
        %fprintf('tocData: %f\n', tocData);
        %fprintf('frame: %f\n', state.internal.zSliceCounter+state.spc.internal.frameDone);
        %fprintf('waitT: %f\n', waitT);
        
        if waitT > 0
            pause(waitT);
        end
        
        if uncaged
            fprintf('Page=%d, Ave page=%d time=%0.2f s (Dt=%0.2f s)  ***Uncaged***\n', state.internal.zSliceCounter, binPage, tocData, tocData - state.spc.acq.timing(state.internal.zSliceCounter+state.spc.internal.frameDone));
        else
            fprintf('Page=%d, Ave page=%d time=%0.2f s (Dt=%0.2f s)\n', state.internal.zSliceCounter, binPage, tocData, tocData - state.spc.acq.timing(state.internal.zSliceCounter+state.spc.internal.frameDone));
        end
        
        
    else
        PQ_dispFLIM(1, 0); %0.13 s.
        spc_writeData(0);
        spc_maxProc_offLine;
    end
    
    %setup imaging.
    nFramesSave = state.acq.numberOfFrames;
    state.spc.internal.lineCounter = 0;
    state.spc.internal.previousLine = [];
    spc.stack.stackF = zeros(state.spc.acq.SPCdata.adc_resolution, ...
        state.acq.linesPerFrame*state.spc.acq.SPCdata.n_channels, state.acq.pixelsPerLine, nFramesSave);

    ret = calllib('TH260lib', 'TH260_StartMeas', state.spc.acq.module, state.spc.internal.Tacq);
end



function FLIM_saveFrameScanning
global state spc gui

%h1 = waitbar(0, 'Saving files: 0', 'Name', 'Saving files', 'WindowStyle', 'modal', 'Pointer', 'watch');
numFrames = state.acq.numberOfFrames;
nCh = state.spc.acq.SPCdata.n_channels;
nLines = state.acq.linesPerFrame;
fileName = [state.files.fullFileName '.tif']; %Regular image;
for frameCounter = 1: numFrames
    spc.imageMod = spc.stack.stackF(:, :, :, frameCounter); %images{1};
    if frameCounter == 1
        spc_writeData(0);
    else
        spc_saveAsTiff(state.spc.files.fullFileName, 1, 0);
    end
    %if mod(frameCounter, 10) == 0
    img1 = spc.imageMod;
    set(gui.spc.figure.projectImage, 'CData', reshape(sum(img1,1), size(img1, 2), size(img1, 3)));
    %waitbar(frameCounter/numFrames, h1, sprintf('Saving frame %d', frameCounter));
    pause(0.001);
    %end
    for i = 1:nCh
        image1 = spc.stack.project(nLines*(i-1)+1:nLines*i, :, frameCounter); %*state.spc.datainfo.pv_per_photon;
        if frameCounter == 1 && i == 1
            %fprintf('Saving %s...\n', fileName);
            imwrite(uint16(image1), fileName, 'WriteMode', 'overwrite', 'compression', 'none', 'Description', state.headerString);
        else
            %fprintf('Appending 0000 %s...\n', fileName);
            imwrite(uint16(image1), fileName, 'WriteMode', 'append', 'compression', 'none');
        end
    end
end

function PQ_saveRegularData
global state spc
fileName = [state.files.fullFileName '.tif'];
nCh = state.spc.acq.SPCdata.n_channels;
siz = size(spc.stack.project(:,:,1));
nLines = siz(1)/nCh;
for i = 1:nCh
    image1 = spc.stack.project(nLines*(i-1)+1:nLines*i, :, 1); %*state.spc.datainfo.pv_per_photon;
    if (state.internal.zSliceCounter == 1 || state.internal.usePage) && i == 1
        %fprintf('Saving %s...\n', fileName);
        imwrite(uint16(image1), fileName, 'WriteMode', 'overwrite', 'compression', 'none', 'Description', state.headerString);
    else
        %fprintf('Appending 0000 %s...\n', fileName);
        imwrite(uint16(image1), fileName, 'WriteMode', 'append', 'compression', 'none');
    end
end
