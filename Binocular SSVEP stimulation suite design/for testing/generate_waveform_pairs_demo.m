
% =========================================================================
% generate_waveform_pairs_demo.m
% Extension of the dual-target demo: THREE stimulus PAIRS (6 circles total),
% one pair per waveform type -- Triangle, Square (50% duty cycle), and Sine
% -- each pair sharing the SAME left-eye/right-eye frequency and phase
% inputs (leftFreqHz/leftPhasePi, rightFreqHz/rightPhasePi).
%
% Layout: left half of the screen shows 3 stacked circles (Triangle-L,
% Square-L, Sine-L); right half shows 3 stacked circles (Triangle-R,
% Square-R, Sine-R). All 3 pairs flicker SIMULTANEOUSLY every trial.
%
% Before the task starts (on the "Press SPACE" screen), all 6 circles are
% shown with a text label inside stating the waveform type and its
% frequency, so the waveform-to-position mapping is visually confirmed
% before data collection begins.
%
% Waveform formulas (all phase-locked using the SAME phase convention as
% the sine, i.e. argument = 2*pi*f*t + phase*pi):
%   Sine:      lum = 0.5*(1 + sin(arg))
%   Triangle:  lum = 0.5*(1 + (2/pi)*asin(sin(arg)))      [Teng et al. 2011 shape]
%   Square:    lum = 0.5*(1 + sign(sin(arg)))             [50% duty cycle]
%
% Uses the ACTUAL measured screen refresh interval (ifi) throughout - never
% the OS-reported nominal rate - for all frame-count and timing calculations.
%
% Outputs:
%   waveform_pairs_events.tsv        -> trial-level event log
%   waveform_pairs_flickerlog.csv    -> frame-level luminance log (6 circles)
%   waveform_pairs_metadata.csv      -> refresh rate + freq/phase metadata
%                                        (needed by the analysis script for
%                                        the independent direct-frame-timing
%                                        frequency method)
%
% Press ESCAPE at any time to stop and exit cleanly (partial data saved).
% =========================================================================

sca; close all; clear;

% ================== CONFIGURABLE STIMULUS PARAMETERS ==================
nTrials = 1;

leftFreqHz   = 5;      % left-eye pair flicker frequency, Hz (all 3 waveforms)
leftPhasePi  = 0;       % left-eye pair initial phase, in units of pi
rightFreqHz  = 12;      % right-eye pair flicker frequency, Hz (all 3 waveforms)
rightPhasePi = 0;     % right-eye pair initial phase, in units of pi

cueDur  = 1.0;   % seconds
gazeDur =3;   % seconds
fsEEG   = 1024;  % Hz, sample-index conversion reference (matches paper convention)

boxSizeCM = 3.0;   % circle diameter, cm
spacingCM = 5.0;   % vertical center-to-center spacing between the 3 stacked circles per eye

waveformNames = {'Triangle', 'Square', 'Sine'};

% ================== SCREEN SETUP ==================
Screen('Preference', 'SkipSyncTests', 0);
screenNum = max(Screen('Screens'));
black = [0 0 0];
white = [255 255 255];

[win, rect] = Screen('OpenWindow', screenNum, black);
screenWidthPx  = RectWidth(rect);
screenHeightPx = RectHeight(rect);

% ---- AUTOMATIC REFRESH RATE DETECTION (measured, NOT nominal) ----
ifi       = Screen('GetFlipInterval', win);   % <-- actual measured refresh interval, used everywhere below
nominalHz = Screen('NominalFrameRate', win);
measuredHz = 1/ifi;
fprintf('Detected screen refresh rate (measured): %.4f Hz (ifi = %.6f s)\n', measuredHz, ifi);
fprintf('OS-reported nominal refresh rate: %.4f Hz (NOT used for timing)\n', nominalHz);

% ---- Geometry: 3 circles stacked vertically in each half ----
[widthMM, ~] = Screen('DisplaySize', screenNum);
pxPerCM   = screenWidthPx / (widthMM/10);
boxSizePx = boxSizeCM * pxPerCM;
spacingPx = spacingCM * pxPerCM;

halfWidthPx = screenWidthPx/2;
leftColX  = halfWidthPx/2;
rightColX = halfWidthPx + halfWidthPx/2;
midY = screenHeightPx/2;
rowY = [midY - spacingPx, midY, midY + spacingPx];   % Triangle, Square, Sine (top to bottom)

leftPos  = [repmat(leftColX,3,1),  rowY(:)];
rightPos = [repmat(rightColX,3,1), rowY(:)];

leftRectStim  = cell(1,3);
rightRectStim = cell(1,3);
for i = 1:3
    leftRectStim{i}  = CenterRectOnPoint([0 0 boxSizePx boxSizePx], leftPos(i,1),  leftPos(i,2));
    rightRectStim{i} = CenterRectOnPoint([0 0 boxSizePx boxSizePx], rightPos(i,1), rightPos(i,2));
end

HideCursor;
Screen('TextSize', win, 18);
Screen('TextColor', win, white);
KbName('UnifyKeyNames');
spaceKey  = KbName('space');
escapeKey = KbName('ESCAPE');

% ---- Save metadata (needed by analysis script for the independent
%      direct-frame-timing frequency method) ----
metaT = table(measuredHz, nominalHz, leftFreqHz, leftPhasePi, rightFreqHz, rightPhasePi, ...
    'VariableNames', {'MeasuredHz_atSetup','NominalHz','LeftFreq_Hz','LeftPhase_pi', ...
                       'RightFreq_Hz','RightPhase_pi'});
writetable(metaT, 'waveform_pairs_metadata.csv');

% ---- Instruction / "Press SPACE" screen: show all 6 labeled circles ----
Screen('FillRect', win, black);
for i = 1:3
    Screen('FrameOval', win, white, leftRectStim{i}, 2);
    Screen('FrameOval', win, white, rightRectStim{i}, 2);
    DrawFormattedText(win, sprintf('%s\n%.2f Hz\n%.2f \x03C0', waveformNames{i}, leftFreqHz, leftPhasePi), ...
        'center', 'center', white, [], [], [], [], [], leftRectStim{i});
    DrawFormattedText(win, sprintf('%s\n%.2f Hz\n%.2f \x03C0', waveformNames{i}, rightFreqHz, rightPhasePi), ...
        'center', 'center', white, [], [], [], [], [], rightRectStim{i});
end
DrawFormattedText(win, 'Press SPACE to begin\n(Press ESC at any time to stop and exit)', ...
    'center', screenHeightPx*0.08, white);
Screen('Flip', win);
KbReleaseWait;
while true
    [keyDown, ~, keyCode] = KbCheck;
    if keyDown && keyCode(spaceKey)
        break;
    elseif keyDown && keyCode(escapeKey)
        sca; ShowCursor;
        fprintf('Aborted before start.\n');
        return;
    end
end

Screen('FillRect', win, black);
t0 = Screen('Flip', win);
abortFlag = false;

eventLog = cell(0,7);   % onset, duration, trial, left_freq, left_phase, right_freq, right_phase
nFramesPerTrial = round(gazeDur/ifi);   % uses ACTUAL measured ifi
frameLogCell = cell(nTrials*nFramesPerTrial, 10);
frameLogRows = 0;

for trialNum = 1:nTrials
    if abortFlag, break; end

    % ---- CUE STAGE ----
    Screen('FillRect', win, black);
    for i = 1:3
        Screen('FillOval', win, white, leftRectStim{i});
        Screen('FillOval', win, white, rightRectStim{i});
    end
    DrawFormattedText(win, '+', 'center', 'center', [255 0 0]);
    Screen('Flip', win);
    abortFlag = waitCheckEscape(cueDur - 0.5*ifi, escapeKey);
    if abortFlag, break; end

    % ---- GAZE STAGE: all 6 circles flicker simultaneously ----
    for f = 1:nFramesPerTrial
        if f == 1
            tRel = 0;
        else
            tRel = (f-1) * ifi;
        end

        argL = 2*pi*leftFreqHz*tRel  + leftPhasePi*pi;
        argR = 2*pi*rightFreqHz*tRel + rightPhasePi*pi;

        lumTriL  = round(255 * 0.5*(1 + (2/pi)*asin(sin(argL))));
        lumSqL   = round(255 * 0.5*(1 + sign(sin(argL))));
        lumSineL = round(255 * 0.5*(1 + sin(argL)));

        lumTriR  = round(255 * 0.5*(1 + (2/pi)*asin(sin(argR))));
        lumSqR   = round(255 * 0.5*(1 + sign(sin(argR))));
        lumSineR = round(255 * 0.5*(1 + sin(argR)));

        lumsL = [lumTriL, lumSqL, lumSineL];
        lumsR = [lumTriR, lumSqR, lumSineR];

        Screen('FillRect', win, black);
        for i = 1:3
            Screen('FillOval', win, [lumsL(i) lumsL(i) lumsL(i)], leftRectStim{i});
            Screen('FillOval', win, [lumsR(i) lumsR(i) lumsR(i)], rightRectStim{i});
        end
        [vbl, ~, ~, missed] = Screen('Flip', win);

        if f == 1
            gazeOnsetVBL = vbl;
        end
        sampleIdx = round((vbl - t0) * fsEEG);

        frameLogRows = frameLogRows + 1;
        frameLogCell(frameLogRows, :) = {trialNum, f, vbl, sampleIdx, ...
            lumTriL, lumSqL, lumSineL, lumTriR, lumSqR, lumSineR};

        [keyDown, ~, keyCode] = KbCheck;
        if keyDown && keyCode(escapeKey)
            abortFlag = true;
            break;
        end
    end
    if abortFlag, break; end

    onsetSample = round((gazeOnsetVBL - t0) * fsEEG);
    eventLog(end+1,:) = {onsetSample, gazeDur, trialNum, leftFreqHz, leftPhasePi, rightFreqHz, rightPhasePi};
end

frameLogCell = frameLogCell(1:frameLogRows, :);

% ================== SAVE EVENT FILE ==================
T = cell2table(eventLog, 'VariableNames', ...
    {'onset','duration','trial','left_freq_Hz','left_phase_pi','right_freq_Hz','right_phase_pi'});
writetable(T, 'waveform_pairs_events.tsv', 'FileType', 'text', 'Delimiter', '\t');

% ================== SAVE FRAME-LEVEL FLICKER LOG ==================
F = cell2table(frameLogCell, 'VariableNames', ...
    {'Trial','FrameNumber','Timestamp_s','Sample_Index','TriL','SqL','SineL','TriR','SqR','SineR'});
writetable(F, 'waveform_pairs_flickerlog.csv');

if abortFlag
    fprintf('ABORTED by user (ESC). Partial data saved.\n');
else
    fprintf('Done. Saved waveform_pairs_events.tsv, waveform_pairs_flickerlog.csv, waveform_pairs_metadata.csv\n');
end

sca;
ShowCursor;

% ========================= LOCAL FUNCTIONS =========================
function abortFlag = waitCheckEscape(duration, escapeKey)
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
