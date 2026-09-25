
% =========================================================================
% generate_LF_stimuli_experiment_v4_square_dualeye.m
% Replicates Experiment 1 (LF condition) of the AR-SSVEP dataset paper
% using Psychtoolbox on a standard monitor, simulating a VR-style
% side-by-side stereo display (left half of screen = left eye,
% right half of screen = right eye).
%
% CHANGES IN THIS VERSION (vs. the original v3):
%   1) Luminance waveform switched from sine (JFPM) to a SQUARE wave with
%      50% duty cycle: lum = 0.5*(1 + sign(sin(2*pi*f*t + phase*pi)))
%      (Teng et al. 2011 found 50% duty-cycle square waves elicit SSVEP
%      with significantly higher accuracy than sine/triangle waves.)
%   2) Frequency AND phase are now independently configurable per eye
%      (leftFreqs_Hz/leftPhases_pi vs rightFreqs_Hz/rightPhases_pi, one
%      value per of the 8 grid positions). Setting left == right gives
%      the original congruent (SFSP) stimulation; setting them differently
%      lets you run SFDP / DFSP / DFDP paradigms directly from this same
%      script -- no need for separate MF/DFDP scripts anymore.
%   3) Runs for a SINGLE session only (the sub-session loop was removed).
%      One .events.tsv file is saved per run.
%   4) Before the "Press SPACE to begin" screen, all 16 circles (8 left-
%      eye + 8 right-eye) are displayed with a text label inside each one
%      showing its own frequency and phase, so the eye/position-to-
%      stimulus mapping can be visually confirmed before data collection.
%
% Outputs (single session):
%   sub-XXX_task-LF_events.tsv          -> trial-level event file
%   sub-XXX_task-LF_flickerlog.csv      -> frame-level luminance log (16 circles)
%   sub-XXX_task-LF_refresh_info.csv    -> detected screen refresh rate
%   sub-XXX_task-LF_stim_metadata.csv   -> box size, spacing, gap, per-eye freq/phase
%
% Press ESCAPE at any time to immediately stop the task and exit cleanly.
% Any data collected before the abort is still saved to disk.
% =========================================================================

sca; close all; clear;

% ================== SUBJECT PARAMETERS ==================
subjectID = '001';
nBlocks   = 2;      % blocks in this single session
targetIDs = 1:8;     % 8 fixed target positions (2x4 grid)

% ================== STIMULUS PARAMETERS (per eye, per grid position) ====
% Set LEFT and RIGHT identically for congruent (SFSP) stimulation, or
% differently to run SFDP / DFSP / DFDP paradigms with this same script.
leftFreqs_Hz    = [8 9 10 11 12 13 14 15];               % Hz, left eye, per position
leftPhases_pi   = [0 0.25 0.5 0.75 1 1.25 1.5 1.75];      % units of pi, left eye
rightFreqs_Hz   = [8 9 10 11 12 13 14 15];                % Hz, right eye, per position
rightPhases_pi  = [0 0.25 0.5 0.75 1 1.25 1.5 1.75];      % units of pi, right eye

cueDur  = 1.0;    % seconds
gazeDur = 3.0;    % seconds
fsEEG   = 1024;   % Hz, matches the paper's EEG sampling rate (for onset/sample conversion)

% ================== DISPLAY / GEOMETRY PARAMETERS ==================
boxSizeCM       = 2;   % diameter of each stimulus circle, in cm
spacingCM       = 4;   % uniform center-to-center spacing between adjacent circles
                          % WITHIN a group (same horizontally and vertically)
interGroupGapCM = 2.5;   % horizontal distance between the left group's rightmost
                          % circle and the right group's leftmost circle
                          % (edge-to-edge gap between the two 2x4 groups)

% ================== SCREEN SETUP ==================
Screen('Preference', 'SkipSyncTests', 0);
screenNum = max(Screen('Screens'));
black = [0 0 0];
white = [255 255 255];

[win, rect] = Screen('OpenWindow', screenNum, black);
screenWidthPx  = RectWidth(rect);
screenHeightPx = RectHeight(rect);

% ---- AUTOMATIC REFRESH RATE DETECTION ----
ifi = Screen('GetFlipInterval', win);
nominalHz = Screen('NominalFrameRate', win);
frameRate = round(1/ifi);
fprintf('Detected screen refresh rate (measured): %.4f Hz (ifi = %.5f s)\n', 1/ifi, ifi);
fprintf('OS-reported nominal refresh rate: %.4f Hz\n', nominalHz);

% ---- Physical screen size -> pixels-per-cm conversion ----
[widthMM, ~] = Screen('DisplaySize', screenNum);
pxPerCM = screenWidthPx / (widthMM/10);
boxSizePx = boxSizeCM * pxPerCM;
spacingPx = spacingCM * pxPerCM;
interGroupGapPx = interGroupGapCM * pxPerCM;

% Save refresh + geometry + per-eye stimulus metadata
refreshInfo = table(1/ifi, nominalHz, frameRate, ...
    'VariableNames', {'Measured_Hz','Nominal_Hz','Rounded_FrameRate_Hz'});
writetable(refreshInfo, sprintf('sub-%s_task-LF_refresh_info.csv', subjectID));

metaInfo = table(boxSizeCM, spacingCM, interGroupGapCM, pxPerCM, boxSizePx, spacingPx, interGroupGapPx, ...
    'VariableNames', {'BoxSize_cm','Spacing_cm','InterGroupGap_cm','PixelsPerCM', ...
                       'BoxSize_px','Spacing_px','InterGroupGap_px'});
stimMeta = table(targetIDs(:), leftFreqs_Hz(:), leftPhases_pi(:), rightFreqs_Hz(:), rightPhases_pi(:), ...
    'VariableNames', {'Position','LeftFreq_Hz','LeftPhase_pi','RightFreq_Hz','RightPhase_pi'});
writetable(metaInfo, sprintf('sub-%s_task-LF_stim_metadata.csv', subjectID));
writetable(stimMeta, sprintf('sub-%s_task-LF_perposition_stim.csv', subjectID));

% ---- Compute BOTH groups' positions as one centered layout ----
nRows = 2; nCols = 4;
groupWidthPx  = (nCols-1)*spacingPx + boxSizePx;
groupHeightPx = (nRows-1)*spacingPx + boxSizePx;
totalWidthPx  = 2*groupWidthPx + interGroupGapPx;

leftGroupOriginX  = (screenWidthPx - totalWidthPx)/2;
rightGroupOriginX = leftGroupOriginX + groupWidthPx + interGroupGapPx;
groupOriginY      = (screenHeightPx - groupHeightPx)/2;

leftPos  = gridPositions(leftGroupOriginX, groupOriginY, nRows, nCols, boxSizePx, spacingPx);
rightPos = gridPositions(rightGroupOriginX, groupOriginY, nRows, nCols, boxSizePx, spacingPx);

HideCursor;
KbName('UnifyKeyNames');
spaceKey  = KbName('space');
escapeKey = KbName('ESCAPE');

% ================== INSTRUCTION SCREEN: SHOW FREQ/PHASE PER CIRCLE ======
Screen('TextSize', win, 16);
Screen('TextColor', win, white);
drawInstructionGrid(win, leftPos, rightPos, boxSizePx, ...
    leftFreqs_Hz, leftPhases_pi, rightFreqs_Hz, rightPhases_pi, black, white);
DrawFormattedText(win, 'Press SPACE to begin\n(Press ESC at any time to stop and exit)', ...
    'center', screenHeightPx*0.06, white);
Screen('Flip', win);
KbReleaseWait;
while true
    [keyDown, ~, keyCode] = KbCheck;
    if keyDown && keyCode(spaceKey)
        break;
    elseif keyDown && keyCode(escapeKey)
        sca; ShowCursor;
        fprintf('Experiment aborted before starting.\n');
        return;
    end
end

% ================== SINGLE-SESSION RUN ==================
Screen('FillRect', win, black);
t0 = Screen('Flip', win);   % session time reference (sample index 0)
abortFlag = false;

eventLog = cell(0,8);   % onset(sample), duration, trial, value, left_freq, left_phase, right_freq, right_phase
frameLogRows = 0;
trialCounter = 0;

% Frame log columns: Block,Trial,FrameNumber,Timestamp_s,Sample_Index,
% L1..L8 (left-eye circle luminance), R1..R8 (right-eye circle luminance)
frameLogCell = cell(nBlocks*8*round(gazeDur*frameRate), 21);

for b = 1:nBlocks
    if abortFlag, break; end

    for cueIdx = 1:8
        if abortFlag, break; end
        trialCounter = trialCounter + 1;
        attendedTarget = targetIDs(cueIdx);

        % ---- CUE STAGE ----
        drawGrid(win, leftPos, rightPos, boxSizePx, [], [], black, white, attendedTarget, true);
        Screen('Flip', win);
        abortFlag = waitCheckEscape(cueDur - 0.5*ifi, escapeKey);
        if abortFlag, break; end

        % ---- GAZE STAGE: ALL 8 positions flicker simultaneously ----
        nFrames = round(gazeDur * frameRate);
        gazeOnsetVBL = [];
        for f = 1:nFrames
            if f == 1
                tRel = 0;
            else
                tRel = (f-1) * ifi;
            end

            % 50%-duty-cycle SQUARE-wave luminance, independent per eye
            lumL = round(255 * 0.5*(1 + sign(sin(2*pi*leftFreqs_Hz*tRel  + leftPhases_pi*pi))));
            lumR = round(255 * 0.5*(1 + sign(sin(2*pi*rightFreqs_Hz*tRel + rightPhases_pi*pi))));

            drawGrid(win, leftPos, rightPos, boxSizePx, lumL, lumR, black, white, [], false);
            [vbl, ~, ~, missed] = Screen('Flip', win);

            if f == 1
                gazeOnsetVBL = vbl;
            end
            sampleIdx = round((vbl - t0) * fsEEG);

            frameLogRows = frameLogRows + 1;
            frameLogCell(frameLogRows, :) = [ {b, trialCounter, f, vbl, sampleIdx}, ...
                num2cell(lumL), num2cell(lumR) ];

            [keyDown, ~, keyCode] = KbCheck;
            if keyDown && keyCode(escapeKey)
                abortFlag = true;
                break;
            end
        end
        if abortFlag, break; end

        onsetSample = round((gazeOnsetVBL - t0) * fsEEG);
        eventLog(end+1,:) = {onsetSample, gazeDur, trialCounter, attendedTarget, ...
            leftFreqs_Hz(attendedTarget), leftPhases_pi(attendedTarget), ...
            rightFreqs_Hz(attendedTarget), rightPhases_pi(attendedTarget)};
    end
end

frameLogCell = frameLogCell(1:frameLogRows, :);

% ================== SAVE EVENT FILE (TSV) ==================
T = cell2table(eventLog, 'VariableNames', ...
    {'onset','duration','trial','value','left_stim_frequency','left_stim_phase', ...
     'right_stim_frequency','right_stim_phase'});
tsvName = sprintf('sub-%s_task-LF_events.tsv', subjectID);
writetable(T, tsvName, 'FileType', 'text', 'Delimiter', '\t');

% ================== SAVE FRAME-LEVEL FLICKER LOG (CSV) ==================
colNames = [{'Block','Trial','FrameNumber','Timestamp_s','Sample_Index'}, ...
    arrayfun(@(x) sprintf('L%d',x), 1:8, 'UniformOutput', false), ...
    arrayfun(@(x) sprintf('R%d',x), 1:8, 'UniformOutput', false)];
F = cell2table(frameLogCell, 'VariableNames', colNames);
csvName = sprintf('sub-%s_task-LF_flickerlog.csv', subjectID);
writetable(F, csvName);

if abortFlag
    fprintf('Session ABORTED by user (ESC). Partial data saved: %s, %s\n', tsvName, csvName);
else
    fprintf('Saved session: %s, %s\n', tsvName, csvName);
end

sca;
ShowCursor;
fprintf('Experiment session ended.\n');

% ========================= LOCAL FUNCTIONS =========================
function abortFlag = waitCheckEscape(duration, escapeKey)
    % Waits for 'duration' seconds while continuously polling for ESCAPE.
    % Returns abortFlag = true immediately if ESCAPE is pressed.
    abortFlag = false;
    if duration <= 0
        return;
    end
    startT = GetSecs;
    while GetSecs - startT < duration
        [keyDown, ~, keyCode] = KbCheck;
        if keyDown && keyCode(escapeKey)
            abortFlag = true;
            return;
        end
        WaitSecs(0.005);
    end
end

function pos = gridPositions(originX, originY, nRows, nCols, boxSizePx, spacingPx)
    % Builds a uniform grid (equal horizontal and vertical center-to-center
    % spacing = spacingPx) whose bounding box's top-left corner is at
    % (originX, originY).
    firstColCenterX = originX + boxSizePx/2;
    firstRowCenterY = originY + boxSizePx/2;

    pos = zeros(nRows*nCols, 2);
    idx = 1;
    for r = 1:nRows
        for c = 1:nCols
            cx = firstColCenterX + (c-1)*spacingPx;
            cy = firstRowCenterY + (r-1)*spacingPx;
            pos(idx,:) = [cx, cy];
            idx = idx + 1;
        end
    end
end

function drawGrid(win, leftPos, rightPos, boxSizePx, lumL, lumR, black, white, cueTarget, isCue)
    Screen('FillRect', win, black);
    for i = 1:8
        if isCue
            colL = black; colR = black;
            if i == cueTarget
                colL = white; colR = white;
            end
        else
            colL = [lumL(i) lumL(i) lumL(i)];
            colR = [lumR(i) lumR(i) lumR(i)];
        end
        rL = CenterRectOnPoint([0 0 boxSizePx boxSizePx], leftPos(i,1), leftPos(i,2));
        rR = CenterRectOnPoint([0 0 boxSizePx boxSizePx], rightPos(i,1), rightPos(i,2));
        Screen('FillOval', win, colL, rL);
        Screen('FillOval', win, colR, rR);
    end
end

function drawInstructionGrid(win, leftPos, rightPos, boxSizePx, leftFreqs, leftPhases, rightFreqs, rightPhases, black, white)
    % Shows all 16 circles (8 left-eye + 8 right-eye) outlined, each
    % labeled with its own frequency (Hz) and phase (units of pi), so the
    % mapping between screen position/eye and stimulus parameters can be
    % visually confirmed before the task starts.
    Screen('FillRect', win, black);
    for i = 1:8
        rL = CenterRectOnPoint([0 0 boxSizePx boxSizePx], leftPos(i,1), leftPos(i,2));
        rR = CenterRectOnPoint([0 0 boxSizePx boxSizePx], rightPos(i,1), rightPos(i,2));
        Screen('FrameOval', win, white, rL, 2);
        Screen('FrameOval', win, white, rR, 2);
        DrawFormattedText(win, sprintf('%.1f Hz\n%.2f \x03C0', leftFreqs(i), leftPhases(i)), ...
            'center', 'center', white, [], [], [], [], [], rL);
        DrawFormattedText(win, sprintf('%.1f Hz\n%.2f \x03C0', rightFreqs(i), rightPhases(i)), ...
            'center', 'center', white, [], [], [], [], [], rR);
    end
end
