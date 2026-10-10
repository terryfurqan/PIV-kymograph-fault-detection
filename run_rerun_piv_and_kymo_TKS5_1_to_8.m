function [masterTable, fsrTable] = run_rerun_piv_and_kymo_TKS5_1_to_8()
% RUN_RERUN_PIV_AND_KYMO_TKS5_1_TO_8  Re-run analisis PIV TANPA frame skip
% (Sequencing = 'consecutive', Skip = 0 -> OVL-S0, 3-Pass 64->32->16 px)
% untuk seluruh 8 eksperimen TKS-5_cm-1 s/d TKS-5_cm-8, dilanjutkan dengan
% Tomografi Spasiotemporal 20 Garis (L01..L20) dan Deteksi Presisi Frame
% Terbentuknya FSR (Fault Surface Rupture) pada Y ≈ 700-710 px (Garis L05).

    here = fileparts(mfilename('fullpath'));
    cd(here);
    if isfile(fullfile(here, 'grain_setup.m'))
        grain_setup();
    end

    baseDir = '/Volumes/Tora 400gb/EXP_coll/TKS/5 cm';
    pivDir  = fullfile(baseDir, 'PIV_2026-06-24');
    outRoot = fullfile(baseDir, 'TKS_5 Compare', 'TKS-5_cm_All_1_to_8_OVL_S0_NoSkip');
    if ~isfolder(outRoot), mkdir(outRoot); end

    nExp       = 8;
    nLines     = 20;
    spacingPx  = 16;
    deadband   = 0.0035;
    intAreas   = [64 32 16 16];
    numWorkers = 8;

    fprintf('==============================================================================================\n');
    fprintf('🚀 RE-RUN FULL PIV TANPA FRAME SKIP (OVL-S0, CONSECUTIVE) + DETEKSI FSR (TKS-5_cm-1 s/d 8)\n');
    fprintf('==============================================================================================\n');

    % Variabel Master
    expNames          = cell(nExp, 1);
    pivMatNames       = cell(nExp, 1);
    rawPhotoCount     = nan(nExp, 1);
    consecPairCount   = nan(nExp, 1);
    deadFrameCount    = nan(nExp, 1);
    deadFrameRanges   = cell(nExp, 1);
    activeFrameCount  = nan(nExp, 1);
    fMotorStart       = nan(nExp, 1);
    fMotorEnd         = nan(nExp, 1);
    meanVelHW_Active  = nan(nExp, 1);
    xFault_L14_Root   = nan(nExp, 1);
    xFault_L10_Mid    = nan(nExp, 1);
    xFault_L05_Y709   = nan(nExp, 1);
    xFault_L03_Top    = nan(nExp, 1);
    faultDip_Deg      = nan(nExp, 1);
    detachment_Y_px   = nan(nExp, 1);
    detachment_MinShr = nan(nExp, 1);
    toeSlump_X_L05    = nan(nExp, 1);
    toeSlump_MinShr   = nan(nExp, 1);

    % Variabel khusus Deteksi FSR (Fault Surface Rupture @ Y ≈ 700-710 px)
    f_NUC_L14_Consec  = nan(nExp, 1);
    f_NUC_L10_Consec  = nan(nExp, 1);
    f_FSR_Onset_0025  = nan(nExp, 1); % Consecutive frame pertama \gamma_xy >= 0.0025 di Y=709px
    f_FSR_Deadband    = nan(nExp, 1); % Consecutive frame pertama \gamma_xy >= 0.0035 (Deadband) di Y=709px
    f_FSR_Strong_0050 = nan(nExp, 1); % Consecutive frame pertama \gamma_xy >= 0.0050 di Y=709px
    f_FSR_FromActive1 = nan(nExp, 1); % Frame ke-berapa sejak motor mulai bergerak (F_FSR - F_MotorStart + 1)
    shr_at_FSR        = nan(nExp, 1);
    max_Shr_L05       = nan(nExp, 1);
    f_Peak_Shr_L05    = nan(nExp, 1);

    montageData = cell(nExp, 1);

    for e = 1:nExp
        expLabel = sprintf('TKS-5_cm-%d', e);
        expNames{e} = expLabel;
        rawMatPath = fullfile(baseDir, sprintf('%s.mat', expLabel));
        expOutDir  = fullfile(outRoot, expLabel);
        if ~isfolder(expOutDir), mkdir(expOutDir); end

        % Cek apakah file OVL-S0-*-3p16px.mat sudah ada di PIV_2026-06-24
        dExist = dir(fullfile(pivDir, sprintf('%s-OVL-S0-*-3p16px.mat', expLabel)));
        if ~isempty(dExist)
            pivMatPath = fullfile(dExist(1).folder, dExist(1).name);
            pivMatNames{e} = dExist(1).name;
            fprintf('\n----------------------------------------------------------------------------------------------\n');
            fprintf('✅ [%d/8] %s: File PIV Tanpa Skip SUDAH ADA -> %s\n', e, expLabel, dExist(1).name);
            fprintf('----------------------------------------------------------------------------------------------\n');
        else
            fprintf('\n----------------------------------------------------------------------------------------------\n');
            fprintf('⚙️  [%d/8] %s: Menjalankan PIV Baru Tanpa Frame Skip (OVL-S0, Consecutive, 64->32->16 px)...\n', e, expLabel);
            fprintf('----------------------------------------------------------------------------------------------\n');
            t0 = tic;
            S_in = load(rawMatPath);
            blobs = S_in.prep.raw.blobs;
            nImgs = numel(blobs);
            clear S_in;

            outFileName = sprintf('%s-OVL-S0-%d-3p16px.mat', expLabel, nImgs);
            pivMatPath  = fullfile(pivDir, outFileName);
            pivMatNames{e} = outFileName;

            tmpRoot = fullfile(tempdir, sprintf('grain_ovls0_%d_%s', e, char(matlab.lang.internal.uuid())));
            rawDir  = fullfile(tmpRoot, 'RAW');
            gsDir   = fullfile(tmpRoot, 'GS');
            mkdir(rawDir); mkdir(gsDir);

            gsFiles = cell(nImgs, 1);
            for k = 1:nImgs
                rawPath = fullfile(rawDir, sprintf('frame_%04d.jpg', k));
                fid = fopen(rawPath, 'wb');
                fwrite(fid, blobs{k}, 'uint8');
                fclose(fid);

                im = imread(rawPath);
                imGs = imresize(im, 0.5);
                gsPath = fullfile(gsDir, sprintf('gs_%04d.jpg', k));
                imwrite(imGs, gsPath, 'JPEG', 'Quality', 92);
                gsFiles{k} = gsPath;
            end
            clear blobs;

            pivResults = PIVlab_automasi(rawDir, ...
                'IntAreas',     intAreas, ...
                'NumPasses',    3, ...
                'Sequencing',   'consecutive', ...
                'Skip',         0, ...
                'NumWorkers',   numWorkers, ...
                'OutputFolder', tmpRoot, ...
                'OutputName',   'piv_ovls0_tmp');

            pivTmpMat = pivResults.output_file;
            nPairs    = pivResults.num_pairs;
            gsPack    = PIVlab_automasi_packgs(gsFiles(1:nPairs), 'Quality', 92, 'ReencodeJpeg', false);

            % Ambil experiment_geometry dari file NOVL referensi
            dRef = dir(fullfile(pivDir, sprintf('%s-NOVL-S1-*-4p20px.mat', expLabel)));
            geom = struct();
            if ~isempty(dRef)
                S_ref = load(fullfile(dRef(1).folder, dRef(1).name), 'experiment_geometry');
                if isfield(S_ref, 'experiment_geometry'), geom = S_ref.experiment_geometry; end
            end
            if isempty(fieldnames(geom))
                geom.X0_cm = 107.45; geom.X1_cm = 108.70; geom.Lpos_cm = 150;
                geom.L0_cm = 42.55;  geom.L1_cm = 41.30;  geom.dL_cm = -1.25;
                geom.strain_cumm = -0.0294; geom.strain_cumm_pct = -2.9377;
                geom.mode = 'shortening'; geom.valid = 1;
                geom.embedded_by = 'run_rerun_piv_and_kymo_TKS5_1_to_8';
            end

            copyfile(pivTmpMat, pivMatPath);
            pivanalyze.io.embedGS(pivMatPath, gsPack, gsDir, 'PAB_step_2');
            pivanalyze.io.embedTimeGeom(pivMatPath, [], geom, false, 'PAB_step_2');
            qpiv_dropped_frames = []; %#ok<NASGU>
            save(pivMatPath, 'qpiv_dropped_frames', '-append');

            i_cleanDir(tmpRoot);
            fprintf('   ✅ Selesai PIV %s (%d pasang konsekutif) dalam %.1f detik -> %s\n', ...
                expLabel, nPairs, toc(t0), outFileName);
        end

        % =================================================================
        % EKSTRAKSI 20 GARIS SPASIOTEMPORAL & DETEKSI FSR PADA DATA OVL-S0
        % =================================================================
        S_piv = load(pivMatPath);
        dataFull = pivcore.data.buildDataset(S_piv);
        clear S_piv;

        nF = dataFull.nFrames;
        consecPairCount(e) = nF;
        rawPhotoCount(e)   = nF + 1;

        x1 = pivcore.data.safeFrame(dataFull.x, 1);
        y1 = pivcore.data.safeFrame(dataFull.y, 1);
        xExt = [min(x1(:)), max(x1(:))];
        yExt = [min(y1(:)), max(y1(:))];
        yMid = (yExt(1) + yExt(2)) / 2;
        yF   = (yExt(2) + yExt(1)) - y1;
        xv   = x1(1, :);
        yv   = y1(:, 1);

        velStack      = cell(1, nF);
        vyStack       = cell(1, nF);
        shrCleanStack = cell(1, nF);
        shrDbStack    = cell(1, nF);

        for f = 1:nF
            [U, V] = pivcore.data.pickAnyVel(dataFull, f);
            vyStack{f}  = -V;
            velStack{f} = hypot(U, V);
            Zraw = pivcore.data.computeShearRate(dataFull, f, 'mode', 'engineering');
            Zcln = imgaussfilt(medfilt2(Zraw, [3 3], 'symmetric'), 1.8);
            Zdb  = Zcln;
            Zdb(abs(Zdb) < deadband) = 0;
            shrCleanStack{f} = Zcln;
            shrDbStack{f}    = Zdb;
        end

        posPct = linspace(2.5, 97.5, nLines)';
        yRow   = yExt(1) + (posPct / 100) * (yExt(2) - yExt(1));
        yAx    = 2 * yMid - yRow;

        kymoVel   = cell(nLines, 1);
        kymoShear = cell(nLines, 1);
        kymoVy    = cell(nLines, 1);
        xSample   = [];

        for k = 1:nLines
            p1 = [xExt(1), yAx(k)];
            p2 = [xExt(2), yAx(k)];
            [Mv, ~, xPts, ~] = i_sampleStackAlongImageLine(x1, y1, velStack, p1, p2, spacingPx);
            [Ms, ~, ~, ~]    = i_sampleStackAlongImageLine(x1, y1, shrCleanStack, p1, p2, spacingPx);
            [Mvy, ~, ~, ~]   = i_sampleStackAlongImageLine(x1, y1, vyStack, p1, p2, spacingPx);
            kymoVel{k}   = Mv;
            kymoShear{k} = Ms;
            kymoVy{k}    = Mvy;
            xSample      = xPts;
        end

        % Deteksi Dead Frames (Pre-run idle & Post-run shutoff) dari kecepatan puncak di garis tengah L10
        peakV_L10 = max(kymoVel{10}, [], 1, 'omitnan');
        ex10 = pivprepFrameExclusion(peakV_L10, nan(1, nF), struct('useMotion', true, 'useTime', false));
        deadIdx = find(ex10.ignore);
        actIdx  = find(~ex10.ignore);
        if isempty(actIdx), actIdx = 1:nF; end

        deadFrameCount(e)   = numel(deadIdx);
        deadFrameRanges{e}  = i_formatRanges(deadIdx);
        activeFrameCount(e) = numel(actIdx);
        fMotorStart(e)      = min(actIdx);
        fMotorEnd(e)        = max(actIdx);

        % Statistik spasial sepanjang fase aktif utama
        fMidAct = actIdx(max(1, round(0.15*numel(actIdx))) : max(1, round(0.85*numel(actIdx))));
        lineID      = cell(nLines, 1);
        meanVelHW   = nan(nLines, 1);
        peakPosShr  = nan(nLines, 1);
        xPosShr     = nan(nLines, 1);
        peakNegShr  = nan(nLines, 1);
        xNegShr     = nan(nLines, 1);
        xVelDrop    = nan(nLines, 1);
        maxVyLine   = nan(nLines, 1);
        zoneLabel   = cell(nLines, 1);

        hwMask  = (xSample >= 300) & (xSample <= 900);
        intMask = (xSample >= 600) & (xSample <= 2400);
        detMask = (xSample >= 150) & (xSample <= 2400);

        for k = 1:nLines
            lineID{k} = sprintf('L%02d', k);
            Mv = kymoVel{k};
            Ms = kymoShear{k};
            Mvy = kymoVy{k};

            meanV_x = mean(Mv(:, fMidAct), 2, 'omitnan');
            maxS_x  = prctile(Ms(:, fMidAct), 90, 2);
            minS_x  = prctile(Ms(:, fMidAct), 10, 2);
            maxVy_x = prctile(Mvy(:, fMidAct), 95, 2);

            meanVelHW(k) = mean(meanV_x(hwMask), 'omitnan');

            sPos = maxS_x; sPos(~intMask) = -Inf;
            [peakPosShr(k), idxP] = max(sPos);
            xPosShr(k) = xSample(idxP);

            sNeg = minS_x; sNeg(~detMask) = Inf;
            [peakNegShr(k), idxN] = min(sNeg);
            xNegShr(k) = xSample(idxN);

            maxVyLine(k) = max(maxVy_x(intMask), [], 'omitnan');

            if meanVelHW(k) > 0.4
                dCand = find((xSample' > 650) & (meanV_x < 0.45 * meanVelHW(k)), 1, 'first');
                if ~isempty(dCand), xVelDrop(k) = xSample(dCand); end
            end
        end

        % Pelacakan Koheren Jejak Sesar Utama (L03 .. L15) dari anchor bagian tengah (L08..L12)
        anchorLines = 8:12;
        [~, bestA] = max(peakPosShr(anchorLines));
        kAnchor = anchorLines(bestA);
        xAnchor = xPosShr(kAnchor);

        xFaultLine   = nan(nLines, 1);
        valFaultLine = nan(nLines, 1);
        xFaultLine(kAnchor)   = xAnchor;
        valFaultLine(kAnchor) = peakPosShr(kAnchor);

        xPrev = xAnchor;
        for k = (kAnchor-1):-1:3
            rowVals = prctile(kymoShear{k}(:, fMidAct), 90, 2)';
            msk = (xSample >= max(650, xPrev - 90)) & (xSample <= min(2400, xPrev + 220));
            rowM = rowVals; rowM(~msk) = -Inf;
            [mxV, cIdx] = max(rowM);
            if isfinite(mxV) && mxV >= 0.0020
                xFaultLine(k)   = xSample(cIdx);
                valFaultLine(k) = mxV;
                xPrev = xFaultLine(k);
            end
        end

        xPrev = xAnchor;
        for k = (kAnchor+1):15
            rowVals = prctile(kymoShear{k}(:, fMidAct), 90, 2)';
            msk = (xSample >= max(550, xPrev - 220)) & (xSample <= min(2300, xPrev + 90));
            rowM = rowVals; rowM(~msk) = -Inf;
            [mxV, cIdx] = max(rowM);
            if isfinite(mxV) && mxV >= 0.0020
                xFaultLine(k)   = xSample(cIdx);
                valFaultLine(k) = mxV;
                xPrev = xFaultLine(k);
            end
        end

        for k = 1:nLines
            if meanVelHW(k) < 0.20 && posPct(k) > 78
                zoneLabel{k} = 'Base / Ruler (Stationary)';
            elseif peakNegShr(k) < -0.012 && xNegShr(k) < 1150 && posPct(k) > 68
                zoneLabel{k} = 'Basal Detachment Horizon';
            elseif isfinite(xFaultLine(k))
                if peakNegShr(k) < -0.005 && xNegShr(k) > xFaultLine(k)
                    zoneLabel{k} = 'Upper Sand + Fore-Thrust & Toe Slump';
                else
                    zoneLabel{k} = 'Active Fore-Thrust Fault Core';
                end
            elseif posPct(k) < 16
                zoneLabel{k} = 'Top Air / Fault Scarp Crest';
            else
                zoneLabel{k} = 'Sand Pack / Transition';
            end
        end

        validFit = false(nLines, 1);
        validFit(4:14) = isfinite(xFaultLine(4:14)) & (valFaultLine(4:14) >= 0.0025);
        if nnz(validFit) >= 3
            pFit = polyfit(yAx(validFit), xFaultLine(validFit), 1);
            faultDip_Deg(e) = atand(1 / abs(pFit(1)));
        end

        meanVelHW_Active(e) = meanVelHW(10);
        xFault_L14_Root(e)  = xFaultLine(14);
        xFault_L10_Mid(e)   = xFaultLine(10);
        xFault_L05_Y709(e)  = xFaultLine(5);
        xFault_L03_Top(e)   = xFaultLine(3);

        detCand = 15:17;
        [minDetVal, idxDetRel] = min(peakNegShr(detCand));
        idxDet = detCand(idxDetRel);
        detachment_Y_px(e)   = yAx(idxDet);
        detachment_MinShr(e) = minDetVal;
        detXmax = xVelDrop(idxDet);
        if isnan(detXmax), detXmax = xFaultLine(14); end

        ms5 = min(kymoShear{5}(:, fMidAct), [], 2, 'omitnan');
        mskToe = (xSample > xFaultLine(5) + 60) & (xSample <= xFaultLine(5) + 350);
        if any(mskToe)
            ms5_t = ms5; ms5_t(~mskToe) = Inf;
            [vToe, iToe] = min(ms5_t);
            if isfinite(vToe) && vToe < -0.0035
                toeSlump_X_L05(e)  = xSample(iToe);
                toeSlump_MinShr(e) = vToe;
            end
        end

        % =================================================================
        % DETEKSI PRESISI FRAME FSR (FAULT SURFACE RUPTURE @ Y ≈ 700-710 px)
        % =================================================================
        cor05 = abs(xSample - xFaultLine(5)) <= 48;
        cor10 = abs(xSample - xFaultLine(10)) <= 48;
        cor14 = abs(xSample - xFaultLine(14)) <= 48;

        c05_raw = max(kymoShear{5}(cor05, :), [], 1, 'omitnan');
        c10_raw = max(kymoShear{10}(cor10, :), [], 1, 'omitnan');
        c14_raw = max(kymoShear{14}(cor14, :), [], 1, 'omitnan');

        % Haluskan ringan 3-frame moving median di sepanjang waktu untuk menolak spike 1-frame
        c05 = movmedian(c05_raw, 3, 'omitnan');
        c10 = movmedian(c10_raw, 3, 'omitnan');
        c14 = movmedian(c14_raw, 3, 'omitnan');

        % Cari frame setelah motor mulai bergerak (f >= fMotorStart(e))
        fSearch = fMotorStart(e):nF;

        i14 = fSearch(find(c14(fSearch) >= deadband, 1, 'first'));
        if ~isempty(i14), f_NUC_L14_Consec(e) = i14; end

        i10 = fSearch(find(c10(fSearch) >= deadband, 1, 'first'));
        if ~isempty(i10), f_NUC_L10_Consec(e) = i10; end

        iOnset = fSearch(find(c05(fSearch) >= 0.0025, 1, 'first'));
        if ~isempty(iOnset), f_FSR_Onset_0025(e) = iOnset; end

        iDb = fSearch(find(c05(fSearch) >= deadband, 1, 'first'));
        if ~isempty(iDb)
            f_FSR_Deadband(e)    = iDb;
            f_FSR_FromActive1(e) = iDb - fMotorStart(e) + 1;
            shr_at_FSR(e)        = c05_raw(iDb);
        end

        iStr = fSearch(find(c05(fSearch) >= 0.0050, 1, 'first'));
        if ~isempty(iStr), f_FSR_Strong_0050(e) = iStr; end

        [max_Shr_L05(e), f_Peak_Shr_L05(e)] = max(c05_raw);

        fprintf('   🎯 [%s] Motor Start = F%03d | NUC(L10) = F%03d | FSR (Y=709px >= 0.0035) = Frame Konsekutif F%03d (Frame Aktif ke-%d sejak gerak) | Strong(>=0.0050) = F%03d\n', ...
            expLabel, fMotorStart(e), f_NUC_L10_Consec(e), f_FSR_Deadband(e), f_FSR_FromActive1(e), f_FSR_Strong_0050(e));

        % Simpan CSV & MAT per eksperimen
        T_lines = table((1:nLines)', lineID, posPct, yAx, yRow, meanVelHW, ...
            xFaultLine, valFaultLine, xNegShr, peakNegShr, xVelDrop, maxVyLine, zoneLabel, ...
            'VariableNames', {'Line_Index', 'Line_ID', 'Pos_Pct_From_Top', 'Y_AxMain_px', 'Y_GridRow_px', ...
            'Mean_Vel_HW', 'X_ForeThrust_px', 'Peak_Pos_Shear', 'X_NegShear_px', 'Peak_Neg_Shear', ...
            'X_VelDrop_px', 'Max_Vy_Uplift', 'Detected_Zone'});
        writetable(T_lines, fullfile(expOutDir, sprintf('%s_20Lines_Spatiotemporal_OVL_S0.csv', expLabel)));
        save(fullfile(expOutDir, sprintf('%s_20Lines_Kymograph_OVL_S0.mat', expLabel)), ...
            'T_lines', 'kymoVel', 'kymoShear', 'kymoVy', 'xSample', 'yAx', 'yRow', 'posPct', ...
            'xFaultLine', 'valFaultLine', 'c05_raw', 'c05', 'c10_raw', 'c10', 'c14_raw', 'c14', ...
            'fMotorStart', 'f_FSR_Deadband');

        % =================================================================
        % RENDER 3 JPG VERIFIKASI PER EKSPERIMEN (OVL-S0 TANPA SKIP)
        % =================================================================
        refFrame = round(0.5 * (fMotorStart(e) + fMotorEnd(e)));
        bgRef  = pivcore.data.bgAt(dataFull, refFrame);
        rgbRef = pivcore.util.grayCLAHE(bgRef, true, true);
        [Uref, Vref] = pivcore.data.pickAnyVel(dataFull, refFrame);
        Zref = shrDbStack{refFrame};
        validF = isfinite(xFaultLine);

        montageData{e} = struct('expLabel', expLabel, 'refFrame', refFrame, 'nF', nF, ...
            'xExt', xExt, 'yExt', yExt, 'x1', x1, 'yF', yF, 'rgbRef', rgbRef, ...
            'Uref', Uref, 'Vref', Vref, 'Zref', Zref, 'yAx', yAx, ...
            'xFaultLine', xFaultLine, 'valFaultLine', valFaultLine, 'faultDip', faultDip_Deg(e), ...
            'idxDet', idxDet, 'detXmax', detXmax, 'xSample', xSample, ...
            'kymoVel5', kymoVel{5}, 'kymoShr5', kymoShear{5}, ...
            'kymoVel10', kymoVel{10}, 'kymoShr10', kymoShear{10}, ...
            'c05_raw', c05_raw, 'c05', c05, 'c10', c10, 'c14', c14, ...
            'fStart', fMotorStart(e), 'fEnd', fMotorEnd(e), ...
            'fNuc10', f_NUC_L10_Consec(e), 'fFsr', f_FSR_Deadband(e), 'fFsrStrong', f_FSR_Strong_0050(e));

        % --- JPG 1: 20 Garis Horizontal + Peta Deteksi Sesar ---
        fig1 = figure('Visible', 'off', 'Color', 'w', 'Units', 'pixels', 'Position', [0 0 2300 1550]);
        i_forceLightFig(fig1);
        tl1 = tiledlayout(fig1, 2, 1, 'TileSpacing', 'compact', 'Padding', 'compact');

        ax1 = nexttile(tl1, 1); hold(ax1, 'on');
        image(ax1, 'XData', xExt, 'YData', [yExt(2) yExt(1)], 'CData', rgbRef);
        set(ax1, 'YDir', 'normal'); axis(ax1, 'image'); xlim(ax1, xExt); ylim(ax1, yExt);
        cmapLines = turbo(nLines);
        for k = 1:nLines
            plot(ax1, xExt, [yAx(k) yAx(k)], '-', 'Color', [0 0 0 0.55], 'LineWidth', 2.0);
            plot(ax1, xExt, [yAx(k) yAx(k)], '--', 'Color', cmapLines(k, :), 'LineWidth', 1.4);
            text(ax1, xExt(1) + 12, yAx(k), sprintf(' L%02d (%4.1f%%) ', k, posPct(k)), ...
                'Color', 'w', 'BackgroundColor', [0 0 0 0.75], 'FontWeight', 'bold', 'FontSize', 8, ...
                'VerticalAlignment', 'middle', 'HorizontalAlignment', 'left', 'Margin', 1);
            text(ax1, xExt(2) - 12, yAx(k), sprintf(' L%02d | Y=%.0f px ', k, yAx(k)), ...
                'Color', [1 0.95 0.3], 'BackgroundColor', [0 0 0 0.75], 'FontWeight', 'bold', 'FontSize', 8, ...
                'VerticalAlignment', 'middle', 'HorizontalAlignment', 'right', 'Margin', 1);
        end
        title(ax1, sprintf('%s (OVL-S0 Frame %d/%d) — Citra Grayscale + 20 Garis Scanline Horizontal (L01 Atas \\rightarrow L20 Bawah)', ...
            strrep(expLabel, '_', '\_'), refFrame, nF), 'FontSize', 12.5, 'FontWeight', 'bold');
        ylabel(ax1, 'Posisi Y (px)', 'FontWeight', 'bold');
        i_styleLightAx(ax1);

        ax2 = nexttile(tl1, 2); hold(ax2, 'on');
        imagesc(ax2, xExt, [yExt(2) yExt(1)], Zref);
        colormap(ax2, jet(256)); clim(ax2, [-0.015, 0.015]);
        image(ax2, 'XData', xExt, 'YData', [yExt(2) yExt(1)], 'CData', rgbRef, 'AlphaData', 0.33);
        pivcore.util.drawGlyphs(ax2, x1, yF, Uref, -Vref, 12, 1.1, [1 1 1]);
        for k = 1:nLines
            plot(ax2, xExt, [yAx(k) yAx(k)], '--', 'Color', [0.1 0.1 0.1 0.60], 'LineWidth', 1.1);
            text(ax2, xExt(1) + 12, yAx(k), sprintf(' L%02d (Y=%.0f) ', k, yAx(k)), ...
                'Color', 'w', 'BackgroundColor', [0 0 0 0.75], 'FontWeight', 'bold', 'FontSize', 8, ...
                'VerticalAlignment', 'middle', 'HorizontalAlignment', 'left', 'Margin', 1);
            if isfinite(xFaultLine(k))
                plot(ax2, xFaultLine(k), yAx(k), 'o', 'MarkerSize', 8.5, ...
                    'MarkerFaceColor', [1 0.95 0], 'MarkerEdgeColor', 'k', 'LineWidth', 1.5);
                text(ax2, xExt(2) - 12, yAx(k), sprintf(' L%02d | X_{sesar}=%.0f px (\\gamma_{xy}=%+.3f) ', k, xFaultLine(k), valFaultLine(k)), ...
                    'Color', [0.65 1 0.65], 'BackgroundColor', [0 0 0 0.78], 'FontWeight', 'bold', 'FontSize', 8, ...
                    'VerticalAlignment', 'middle', 'HorizontalAlignment', 'right', 'Margin', 1);
            elseif k == idxDet
                xDetEnd = min(2000, max(700, detXmax));
                plot(ax2, [200 xDetEnd], [yAx(k) yAx(k)], '-', 'Color', [0 1 1], 'LineWidth', 3.0);
                text(ax2, xExt(2) - 12, yAx(k), sprintf(' L%02d | Detachment Basal X=200..%.0f px (\\gamma_{xy}=%+.3f) ', k, xDetEnd, detachment_MinShr(e)), ...
                    'Color', [0.4 0.95 1], 'BackgroundColor', [0 0 0 0.78], 'FontWeight', 'bold', 'FontSize', 8, ...
                    'VerticalAlignment', 'middle', 'HorizontalAlignment', 'right', 'Margin', 1);
            end
        end
        if any(validF)
            plot(ax2, xFaultLine(validF), yAx(validF), '-y', 'LineWidth', 2.4);
        end
        set(ax2, 'YDir', 'normal'); axis(ax2, 'image'); xlim(ax2, xExt); ylim(ax2, yExt);
        cb2 = colorbar(ax2, 'eastoutside'); cb2.Label.String = 'Cleaned \gamma_{xy} [\pm0.015]'; cb2.Color = 'k';
        title(ax2, sprintf('%s (OVL-S0 Frame %d/%d) — Deteksi Spasiotemporal 20 Garis (Dip \\approx %.1f^\\circ | FSR @ Frame %d)', ...
            strrep(expLabel, '_', '\_'), refFrame, nF, faultDip_Deg(e), f_FSR_Deadband(e)), 'FontSize', 12.5, 'FontWeight', 'bold');
        xlabel(ax2, 'Posisi X sepanjang Sandbox (px)', 'FontWeight', 'bold');
        ylabel(ax2, 'Posisi Y (px)', 'FontWeight', 'bold');
        i_styleLightAx(ax2);

        exportgraphics(fig1, fullfile(expOutDir, sprintf('%s_20_Garis_Horizontal_L01_L20.jpg', expLabel)), 'Resolution', 140, 'BackgroundColor', 'white');
        close(fig1);

        % --- JPG 2: Dashboard Kymograph (axPSG) & Time-Series (axPOT) + Penanda FSR ---
        fig2 = figure('Visible', 'off', 'Color', 'w', 'Units', 'pixels', 'Position', [0 0 2350 1700]);
        i_forceLightFig(fig2);
        tl2 = tiledlayout(fig2, 3, 2, 'TileSpacing', 'compact', 'Padding', 'compact');
        title(tl2, sprintf('%s — Kymograph (axPSG) & Time-Series (axPOT) Tanpa Frame Skip (%d Pasangan Konsekutif | Motor Start: F%03d | FSR @ Y=709px: F%03d)', ...
            strrep(expLabel, '_', '\_'), nF, fMotorStart(e), f_FSR_Deadband(e)), 'FontSize', 13.5, 'FontWeight', 'bold', 'Color', 'k');

        axK1 = nexttile(tl2, 1);
        imagesc(axK1, 1:nF, xSample, kymoVel{5}); colormap(axK1, turbo(256)); clim(axK1, [0 2.0]); set(axK1, 'YDir', 'normal');
        hold(axK1, 'on');
        if isfinite(xFaultLine(5)), yline(axK1, xFaultLine(5), '--w', sprintf('Sesar L05 X≈%.0f px', xFaultLine(5)), 'LineWidth', 1.6, 'FontWeight', 'bold'); end
        if isfinite(f_FSR_Deadband(e)), xline(axK1, f_FSR_Deadband(e), '-g', sprintf('FSR (F%03d)', f_FSR_Deadband(e)), 'LineWidth', 2.0, 'FontWeight', 'bold'); end
        hold(axK1, 'off');
        ylabel(axK1, 'Posisi X (px)', 'FontWeight', 'bold');
        title(axK1, sprintf('[1A] Kymograph |V| — Garis L05 (Y = %.0f px, %d Frame Konsekutif)', yAx(5), nF), 'FontWeight', 'bold');
        cbK1 = colorbar(axK1); cbK1.Label.String = '|V| (px/fr)'; cbK1.Color = 'k';
        i_styleLightAx(axK1);

        axK2 = nexttile(tl2, 2);
        imagesc(axK2, 1:nF, xSample, kymoShear{5}); colormap(axK2, jet(256)); clim(axK2, [-0.012 0.012]); set(axK2, 'YDir', 'normal');
        hold(axK2, 'on');
        if isfinite(xFaultLine(5)), yline(axK2, xFaultLine(5), '--k', sprintf('Fore-Thrust X≈%.0f px', xFaultLine(5)), 'LineWidth', 1.6, 'FontWeight', 'bold'); end
        if isfinite(f_FSR_Deadband(e)), xline(axK2, f_FSR_Deadband(e), '-g', sprintf('FSR = F%03d', f_FSR_Deadband(e)), 'LineWidth', 2.0, 'FontWeight', 'bold'); end
        hold(axK2, 'off');
        ylabel(axK2, 'Posisi X (px)', 'FontWeight', 'bold');
        title(axK2, sprintf('[1B] Kymograph Cleaned \\gamma_{xy} — Garis L05 (Y = %.0f px) [FSR = Frame %d]', yAx(5), f_FSR_Deadband(e)), 'FontWeight', 'bold');
        cbK2 = colorbar(axK2); cbK2.Label.String = '\gamma_{xy}'; cbK2.Color = 'k';
        i_styleLightAx(axK2);

        axK3 = nexttile(tl2, 3);
        imagesc(axK3, 1:nF, xSample, kymoVel{10}); colormap(axK3, turbo(256)); clim(axK3, [0 2.0]); set(axK3, 'YDir', 'normal');
        hold(axK3, 'on');
        if isfinite(xFaultLine(10)), yline(axK3, xFaultLine(10), '--w', sprintf('Sesar L10 X≈%.0f px', xFaultLine(10)), 'LineWidth', 1.6, 'FontWeight', 'bold'); end
        if isfinite(f_NUC_L10_Consec(e)), xline(axK3, f_NUC_L10_Consec(e), '-m', sprintf('NUC (F%03d)', f_NUC_L10_Consec(e)), 'LineWidth', 1.8, 'FontWeight', 'bold'); end
        hold(axK3, 'off');
        ylabel(axK3, 'Posisi X (px)', 'FontWeight', 'bold');
        title(axK3, sprintf('[2A] Kymograph |V| — Garis Tengah L10 (Y = %.0f px)', yAx(10)), 'FontWeight', 'bold');
        cbK3 = colorbar(axK3); cbK3.Label.String = '|V| (px/fr)'; cbK3.Color = 'k';
        i_styleLightAx(axK3);

        axK4 = nexttile(tl2, 4);
        imagesc(axK4, 1:nF, xSample, kymoShear{10}); colormap(axK4, jet(256)); clim(axK4, [-0.015 0.015]); set(axK4, 'YDir', 'normal');
        hold(axK4, 'on');
        if isfinite(xFaultLine(10)), yline(axK4, xFaultLine(10), '--k', sprintf('Fore-Thrust X≈%.0f px', xFaultLine(10)), 'LineWidth', 1.6, 'FontWeight', 'bold'); end
        if isfinite(f_NUC_L10_Consec(e)), xline(axK4, f_NUC_L10_Consec(e), '-m', sprintf('NUC = F%03d', f_NUC_L10_Consec(e)), 'LineWidth', 1.8, 'FontWeight', 'bold'); end
        if isfinite(f_FSR_Deadband(e)), xline(axK4, f_FSR_Deadband(e), '-g', sprintf('FSR = F%03d', f_FSR_Deadband(e)), 'LineWidth', 1.8, 'FontWeight', 'bold'); end
        hold(axK4, 'off');
        ylabel(axK4, 'Posisi X (px)', 'FontWeight', 'bold');
        title(axK4, sprintf('[2B] Kymograph Cleaned \\gamma_{xy} — Garis Tengah L10 (Y = %.0f px)', yAx(10)), 'FontWeight', 'bold');
        cbK4 = colorbar(axK4); cbK4.Label.String = '\gamma_{xy}'; cbK4.Color = 'k';
        i_styleLightAx(axK4);

        axK5 = nexttile(tl2, 5); hold(axK5, 'on');
        M10v = kymoVel{10};
        for r = 1:size(M10v, 1)
            plot(axK5, 1:nF, M10v(r, :), '-', 'Color', [0.65 0.65 0.68 0.22]);
        end
        xf10 = xFaultLine(10); if isnan(xf10), xf10 = 1228; end
        isHW = (xSample >= 250) & (xSample < xf10 - 80);
        isFW = (xSample > xf10 + 120);
        hPk = plot(axK5, 1:nF, peakV_L10, '-k', 'LineWidth', 2.0);
        hHW = plot(axK5, 1:nF, mean(M10v(isHW, :), 1, 'omitnan'), '-r', 'LineWidth', 1.9);
        hFW = plot(axK5, 1:nF, mean(M10v(isFW, :), 1, 'omitnan'), '-b', 'LineWidth', 1.9);
        yline(axK5, ex10.motionMin, '--r', sprintf('Dead Threshold (%.2f px/fr)', ex10.motionMin), 'LineWidth', 1.3);
        xline(axK5, fMotorStart(e), '-k', sprintf('Motor Start (F%03d)', fMotorStart(e)), 'LineWidth', 1.6);
        grid(axK5, 'on'); xlim(axK5, [1 nF]);
        xlabel(axK5, sprintf('Consecutive Frame Pair (1 .. %d)', nF), 'FontWeight', 'bold');
        ylabel(axK5, '|V| (px/frame)', 'FontWeight', 'bold');
        title(axK5, sprintf('[3A] axPOT Time-Series |V| — Dead Frames: [%s] | Motor Start: F%03d', deadFrameRanges{e}, fMotorStart(e)), 'FontWeight', 'bold');
        lg5 = legend(axK5, [hPk, hHW, hFW], {'Peak |V|', 'Mean Hanging Wall', 'Mean Footwall'}, 'Location', 'northeast');
        lg5.Color = [1 1 1]; lg5.TextColor = [0 0 0];
        i_styleLightAx(axK5);

        axK6 = nexttile(tl2, 6); hold(axK6, 'on');
        h14 = plot(axK6, 1:nF, c14, ':k', 'LineWidth', 1.5);
        h10 = plot(axK6, 1:nF, c10, '--r', 'LineWidth', 1.9);
        h05 = plot(axK6, 1:nF, c05, '-', 'Color', [0.0 0.45 0.85], 'LineWidth', 2.4);
        plot(axK6, 1:nF, c05_raw, '-', 'Color', [0.0 0.45 0.85 0.30], 'LineWidth', 1.0);
        yline(axK6, deadband, '--', 'Color', [0.1 0.65 0.2], 'LineWidth', 1.5, 'Label', 'Ambang FSR (+0.0035)');
        if isfinite(f_FSR_Deadband(e))
            fDb = f_FSR_Deadband(e);
            plot(axK6, fDb, c05(fDb), 'o', 'MarkerSize', 10, 'MarkerFaceColor', [0.1 0.8 0.25], 'MarkerEdgeColor', 'k', 'LineWidth', 1.8);
            xline(axK6, fDb, '-', 'Color', [0.1 0.65 0.2], 'LineWidth', 1.8, 'Label', sprintf('FSR = Frame %d (Aktif ke-%d)', fDb, f_FSR_FromActive1(e)), 'FontWeight', 'bold');
        end
        grid(axK6, 'on'); xlim(axK6, [1 nF]);
        xlabel(axK6, sprintf('Consecutive Frame Pair (1 .. %d)', nF), 'FontWeight', 'bold');
        ylabel(axK6, 'Peak +\gamma_{xy} Inti Sesar', 'FontWeight', 'bold');
        title(axK6, sprintf('[3B] Propagasi Sesar dari Bawah ke Permukaan -> FSR @ Y=709px Terbentuk pada Frame %d', f_FSR_Deadband(e)), 'FontWeight', 'bold');
        lg6 = legend(axK6, [h05, h10, h14], {'L05 Permukaan (Y=709 px) [FSR]', 'L10 Tengah (Y=484 px)', 'L14 Akar Ramp (Y=304 px)'}, 'Location', 'northwest');
        lg6.Color = [1 1 1]; lg6.TextColor = [0 0 0];
        i_styleLightAx(axK6);

        exportgraphics(fig2, fullfile(expOutDir, sprintf('%s_PSG_Y710px_dan_Tengah_Dashboard.jpg', expLabel)), 'Resolution', 140, 'BackgroundColor', 'white');
        close(fig2);

        % --- JPG 3: 3 Momen Kunci (1: Pre-FSR / NUC, 2: Tepat Momen FSR, 3: Fase Klimaks/Late) ---
        fig3 = figure('Visible', 'off', 'Color', 'w', 'Units', 'pixels', 'Position', [0 0 2250 1700]);
        i_forceLightFig(fig3);
        tl3 = tiledlayout(fig3, 3, 1, 'TileSpacing', 'compact', 'Padding', 'compact');
        fPreFsr = max(1, f_FSR_Deadband(e) - 3);
        fAtFsr  = max(1, min(nF, f_FSR_Deadband(e)));
        fMature = refFrame;
        frList  = [fPreFsr, fAtFsr, fMature];
        stNames = {
            sprintf('SEBELUM FSR (Frame %03d/%03d) — Sesar Baru Tumbuh di Bawah/Tengah, Belum Menembus Y=709 px', fPreFsr, nF), ...
            sprintf('MOMEN TERBENTUKNYA FSR (Frame %03d/%03d, Aktif ke-%d) — Shear Strain Pertama Kali Menembus Y=709 px (L05)', fAtFsr, nF, f_FSR_FromActive1(e)), ...
            sprintf('FASE MATANG / KLIMAKS (Frame %03d/%03d) — Sesar Penuh dari Akar Ramp ke Permukaan & Gawir Sesar', fMature, nF)
        };

        title(tl3, sprintf('%s (OVL-S0 Tanpa Skip) — Bukti Visual Pembentukan FSR pada Frame %03d', ...
            strrep(expLabel, '_', '\_'), fAtFsr), 'FontSize', 14, 'FontWeight', 'bold', 'Color', 'k');

        for idx = 1:3
            f = frList(idx);
            ax = nexttile(tl3, idx); hold(ax, 'on');
            bgF  = pivcore.data.bgAt(dataFull, f);
            rgbF = pivcore.util.grayCLAHE(bgF, true, true);
            [Uf, Vf] = pivcore.data.pickAnyVel(dataFull, f);
            Zf = shrDbStack{f};

            imagesc(ax, xExt, [yExt(2) yExt(1)], Zf);
            colormap(ax, jet(256)); clim(ax, [-0.015, 0.015]);
            image(ax, 'XData', xExt, 'YData', [yExt(2) yExt(1)], 'CData', rgbF, 'AlphaData', 0.34);
            pivcore.util.drawGlyphs(ax, x1, yF, Uf, -Vf, 12, 1.1, [1 1 1]);

            for kk = [3, 5, 10, idxDet]
                lw = 1.1; colL = '--k';
                if kk == 5, lw = 2.0; colL = '-g'; end
                plot(ax, xExt, [yAx(kk) yAx(kk)], colL, 'LineWidth', lw);
                text(ax, xExt(1)+15, yAx(kk)+18, sprintf('L%02d (Y=%.0f px)', kk, yAx(kk)), ...
                    'Color', 'w', 'BackgroundColor', [0 0 0 0.72], 'FontWeight', 'bold', 'FontSize', 8.5);
            end
            if any(validF)
                plot(ax, xFaultLine(validF), yAx(validF), '-y', 'LineWidth', 2.0);
                plot(ax, xFaultLine(5), yAx(5), 'go', 'MarkerFaceColor', 'g', 'MarkerSize', 10, 'LineWidth', 2.0);
            end
            set(ax, 'YDir', 'normal'); axis(ax, 'image'); xlim(ax, xExt); ylim(ax, yExt);
            cb = colorbar(ax, 'eastoutside'); cb.Label.String = '\gamma_{xy} [\pm0.015]'; cb.Color = 'k';
            title(ax, sprintf('[%d] %s', idx, stNames{idx}), 'FontWeight', 'bold', 'FontSize', 11.5);
            ylabel(ax, 'Posisi Y (px)', 'FontWeight', 'bold');
            if idx == 3, xlabel(ax, 'Posisi X sepanjang Sandbox (px)', 'FontWeight', 'bold'); end
            i_styleLightAx(ax);
        end
        exportgraphics(fig3, fullfile(expOutDir, sprintf('%s_Evolusi_3Fase_PreFSR_FSR_Mature.jpg', expLabel)), 'Resolution', 140, 'BackgroundColor', 'white');
        close(fig3);

        clear dataFull velStack vyStack shrCleanStack shrDbStack;
    end

    % =====================================================================
    % SIMPAN TABEL MASTER & TABEL DETEKSI FSR (OVL-S0 TANPA SKIP)
    % =====================================================================
    masterTable = table((1:nExp)', expNames, pivMatNames, rawPhotoCount, consecPairCount, ...
        deadFrameCount, deadFrameRanges, activeFrameCount, fMotorStart, fMotorEnd, ...
        f_NUC_L14_Consec, f_NUC_L10_Consec, f_FSR_Onset_0025, f_FSR_Deadband, f_FSR_FromActive1, f_FSR_Strong_0050, ...
        xFault_L14_Root, xFault_L10_Mid, xFault_L05_Y709, xFault_L03_Top, faultDip_Deg, ...
        detachment_Y_px, detachment_MinShr, toeSlump_X_L05, toeSlump_MinShr, ...
        'VariableNames', {'Exp_No', 'Experiment_ID', 'PIV_OVL_S0_File', 'Raw_Photos', 'Consecutive_Pairs', ...
        'Dead_Frames_Count', 'Dead_Frames_Indices', 'Active_Frames_Count', 'Frame_Motor_Start', 'Frame_Motor_End', ...
        'Frame_NUC_L14', 'Frame_NUC_L10', 'Frame_FSR_Onset_0025', 'Frame_FSR_Deadband_0035', 'FSR_Active_Step_From_Start', 'Frame_FSR_Strong_0050', ...
        'X_Fault_L14_px', 'X_Fault_L10_px', 'X_Fault_L05_Y709_px', 'X_Fault_L03_px', 'Fault_Dip_Deg', ...
        'Detachment_Y_px', 'Detachment_Min_Shear', 'ToeSlump_X_L05_px', 'ToeSlump_Min_Shear'});

    fsrTable = table((1:nExp)', expNames, consecPairCount, deadFrameRanges, fMotorStart, ...
        f_NUC_L10_Consec, f_FSR_Onset_0025, f_FSR_Deadband, f_FSR_FromActive1, f_FSR_Strong_0050, ...
        shr_at_FSR, max_Shr_L05, f_Peak_Shr_L05, xFault_L05_Y709, faultDip_Deg, ...
        'VariableNames', {'Exp_No', 'Experiment_ID', 'Total_Consec_Frames', 'Dead_Frames_PrePost', 'Frame_Motor_Start', ...
        'Frame_NUC_Mid_L10', 'Frame_FSR_Onset_0025', 'Frame_FSR_Y709_Deadband', 'FSR_Step_After_Motor_Start', 'Frame_FSR_Strong_0050', ...
        'Shear_at_FSR', 'Max_Shear_L05', 'Frame_Peak_Shear_L05', 'X_Fault_L05_px', 'Fault_Dip_Deg'});

    disp('==============================================================================================');
    disp('📋 TABEL HASIL DETEKSI FRAME FSR (OVL-S0 TANPA FRAME SKIP) — TKS-5_cm-1 s/d TKS-5_cm-8:');
    disp('==============================================================================================');
    disp(fsrTable);

    writetable(masterTable, fullfile(outRoot, 'TKS-5_cm_All_1_to_8_OVL_S0_Master_Summary.csv'));
    writetable(fsrTable,    fullfile(outRoot, 'TKS-5_cm_All_1_to_8_OVL_S0_FSR_Detection.csv'));
    save(fullfile(outRoot, 'TKS-5_cm_All_1_to_8_OVL_S0_Summary.mat'), 'masterTable', 'fsrTable', 'montageData');

    % =====================================================================
    % RENDER 3 MASTER MONTAGES (4x2) LINTAS 8 EKSPERIMEN (OVL-S0)
    % =====================================================================
    % 1) Montage Peta Deteksi Sesar 20 Garis (4x2)
    figM1 = figure('Visible', 'off', 'Color', 'w', 'Units', 'pixels', 'Position', [0 0 2600 1850]);
    i_forceLightFig(figM1);
    tlM1 = tiledlayout(figM1, 4, 2, 'TileSpacing', 'compact', 'Padding', 'compact');
    title(tlM1, 'KOMPARASI SPASIOTEMPORAL 20 GARIS TANPA FRAME SKIP (OVL-S0): TKS-5\_cm-1 s/d 8 — Jejak Sesar (Kuning) & Frame FSR', ...
        'FontSize', 15, 'FontWeight', 'bold', 'Color', 'k');

    for e = 1:nExp
        md = montageData{e};
        ax = nexttile(tlM1, e); hold(ax, 'on');
        imagesc(ax, md.xExt, [md.yExt(2) md.yExt(1)], md.Zref);
        colormap(ax, jet(256)); clim(ax, [-0.015, 0.015]);
        image(ax, 'XData', md.xExt, 'YData', [md.yExt(2) md.yExt(1)], 'CData', md.rgbRef, 'AlphaData', 0.34);
        pivcore.util.drawGlyphs(ax, md.x1, md.yF, md.Uref, -md.Vref, 14, 1.05, [1 1 1]);
        for k = [3, 5, 10, 14, md.idxDet]
            plot(ax, md.xExt, [md.yAx(k) md.yAx(k)], '--', 'Color', [0.1 0.1 0.1 0.65], 'LineWidth', 1.0);
        end
        xDetEnd = min(2000, max(700, md.detXmax));
        plot(ax, [200 xDetEnd], [md.yAx(md.idxDet) md.yAx(md.idxDet)], '-c', 'LineWidth', 2.6);
        vf = isfinite(md.xFaultLine);
        if any(vf)
            plot(ax, md.xFaultLine(vf), md.yAx(vf), '-y', 'LineWidth', 2.4);
            plot(ax, md.xFaultLine(vf), md.yAx(vf), 'ko', 'MarkerFaceColor', 'y', 'MarkerSize', 6);
            plot(ax, md.xFaultLine(5), md.yAx(5), 'go', 'MarkerFaceColor', 'g', 'MarkerSize', 9, 'LineWidth', 1.8);
        end
        set(ax, 'YDir', 'normal'); axis(ax, 'image'); xlim(ax, md.xExt); ylim(ax, md.yExt);
        cb = colorbar(ax, 'eastoutside'); cb.Color = 'k';
        title(ax, sprintf('[%d] %s (F%03d/%03d) | Motor Start: F%02d -> FSR(Y=709px): Frame F%02d (Aktif ke-%d) | Dip \\approx %.1f^\\circ', ...
            e, strrep(md.expLabel, '_', '\_'), md.refFrame, md.nF, md.fStart, md.fFsr, f_FSR_FromActive1(e), md.faultDip), ...
            'FontWeight', 'bold', 'FontSize', 10.2);
        ylabel(ax, 'Y (px)', 'FontWeight', 'bold');
        if e >= 7, xlabel(ax, 'X (px)', 'FontWeight', 'bold'); end
        i_styleLightAx(ax);
    end
    exportgraphics(figM1, fullfile(outRoot, 'TKS-5_cm_All_1_to_8_OVL_S0_Fault_Map_Montage_4x2.jpg'), 'Resolution', 150, 'BackgroundColor', 'white');
    close(figM1);

    % 2) Montage Kymograph axPSG \gamma_xy pada L05 (Y=709 px) dengan Garis FSR
    figM2 = figure('Visible', 'off', 'Color', 'w', 'Units', 'pixels', 'Position', [0 0 2500 1800]);
    i_forceLightFig(figM2);
    tlM2 = tiledlayout(figM2, 4, 2, 'TileSpacing', 'compact', 'Padding', 'compact');
    title(tlM2, 'KOMPARASI KYMOGRAPH (axPSG) \gamma_{xy} TANPA FRAME SKIP (OVL-S0) PADA Y \approx 709 px (GARIS L05) & DETEKSI FRAME FSR', ...
        'FontSize', 14.5, 'FontWeight', 'bold', 'Color', 'k');

    for e = 1:nExp
        md = montageData{e};
        ax = nexttile(tlM2, e);
        imagesc(ax, 1:md.nF, md.xSample, md.kymoShr5);
        colormap(ax, jet(256)); clim(ax, [-0.012 0.012]); set(ax, 'YDir', 'normal');
        hold(ax, 'on');
        if isfinite(md.xFaultLine(5))
            yline(ax, md.xFaultLine(5), '--k', sprintf('Sesar L05 X≈%.0f px', md.xFaultLine(5)), 'LineWidth', 1.6, 'FontWeight', 'bold');
        end
        xline(ax, md.fStart, ':w', sprintf('Start F%02d', md.fStart), 'LineWidth', 1.5, 'FontWeight', 'bold');
        if isfinite(md.fFsr)
            xline(ax, md.fFsr, '-g', sprintf('FSR = F%02d', md.fFsr), 'LineWidth', 2.2, 'FontWeight', 'bold');
        end
        hold(ax, 'off');
        cb = colorbar(ax, 'eastoutside'); cb.Label.String = '\gamma_{xy}'; cb.Color = 'k';
        ylabel(ax, 'Posisi X (px)', 'FontWeight', 'bold');
        if e >= 7, xlabel(ax, 'Consecutive Frame Pair Index', 'FontWeight', 'bold'); end
        title(ax, sprintf('[%d] %s (%d Pairs) — Motor Start: F%02d | NUC(L10): F%02d | FSR(L05 Y=709px): Frame F%02d', ...
            e, strrep(md.expLabel, '_', '\_'), md.nF, md.fStart, md.fNuc10, md.fFsr), ...
            'FontWeight', 'bold', 'FontSize', 10.2);
        i_styleLightAx(ax);
    end
    exportgraphics(figM2, fullfile(outRoot, 'TKS-5_cm_All_1_to_8_OVL_S0_Kymograph_Y710_Montage_4x2.jpg'), 'Resolution', 150, 'BackgroundColor', 'white');
    close(figM2);

    % 3) Montage Kurva Time-Series Propagasi Sesar (L14 -> L10 -> L05 = FSR)
    figM3 = figure('Visible', 'off', 'Color', 'w', 'Units', 'pixels', 'Position', [0 0 2450 1750]);
    i_forceLightFig(figM3);
    tlM3 = tiledlayout(figM3, 4, 2, 'TileSpacing', 'compact', 'Padding', 'compact');
    title(tlM3, 'KURVA EVOLUSI WAKTU (axPOT) TANPA FRAME SKIP (OVL-S0): PENENTUAN PRESISI FRAME FSR PADA Y \approx 709 px (L05)', ...
        'FontSize', 14.5, 'FontWeight', 'bold', 'Color', 'k');

    for e = 1:nExp
        md = montageData{e};
        ax = nexttile(tlM3, e); hold(ax, 'on');
        % Arsir dead frames awal bila fStart > 1
        if md.fStart > 1
            patch(ax, [0.5, md.fStart-0.5, md.fStart-0.5, 0.5], [-0.005, -0.005, 0.030, 0.030], ...
                [1 0.45 0.45], 'FaceAlpha', 0.20, 'EdgeColor', 'none');
        end
        h14 = plot(ax, 1:md.nF, md.c14, ':k', 'LineWidth', 1.4);
        h10 = plot(ax, 1:md.nF, md.c10, '--r', 'LineWidth', 1.8);
        plot(ax, 1:md.nF, md.c05_raw, '-', 'Color', [0.0 0.45 0.85 0.30], 'LineWidth', 1.0);
        h05 = plot(ax, 1:md.nF, md.c05, '-', 'Color', [0.0 0.45 0.85], 'LineWidth', 2.4);

        yline(ax, deadband, '--', 'Color', [0.1 0.65 0.2], 'LineWidth', 1.4);
        xline(ax, md.fStart, ':k', sprintf('Start F%02d', md.fStart), 'LineWidth', 1.4);
        if isfinite(md.fFsr)
            plot(ax, md.fFsr, md.c05(md.fFsr), 'o', 'MarkerSize', 9.5, ...
                'MarkerFaceColor', [0.1 0.8 0.25], 'MarkerEdgeColor', 'k', 'LineWidth', 1.8);
            xline(ax, md.fFsr, '-', 'Color', [0.1 0.65 0.2], 'LineWidth', 1.9);
            text(ax, md.fFsr + 1.5, max(0.012, md.c05(md.fFsr) + 0.003), ...
                sprintf('FSR = Frame %d\n(Aktif ke-%d)', md.fFsr, f_FSR_FromActive1(e)), ...
                'Color', [0.05 0.45 0.15], 'BackgroundColor', [0.92 1.0 0.92], 'EdgeColor', [0.1 0.65 0.2], ...
                'FontWeight', 'bold', 'FontSize', 8.5, 'Margin', 2);
        end
        grid(ax, 'on'); xlim(ax, [1 md.nF]); ylim(ax, [-0.002, 0.028]);
        title(ax, sprintf('[%d] %s — Motor Start: F%02d | NUC(L10): F%02d | FSR(Y=709px): Frame F%02d (Aktif ke-%d)', ...
            e, strrep(md.expLabel, '_', '\_'), md.fStart, md.fNuc10, md.fFsr, f_FSR_FromActive1(e)), ...
            'FontWeight', 'bold', 'FontSize', 10.2);
        ylabel(ax, 'Peak +\gamma_{xy}', 'FontWeight', 'bold');
        if e >= 7, xlabel(ax, 'Consecutive Frame Pair Index', 'FontWeight', 'bold'); end
        if e == 1
            lg = legend(ax, [h05, h10, h14], {'Garis Permukaan L05 (Y=709 px) [FSR]', 'Garis Tengah L10 (Y=484 px)', 'Garis Akar L14 (Y=304 px)'}, ...
                'Location', 'northeast', 'FontSize', 8);
            lg.Color = [1 1 1]; lg.TextColor = [0 0 0];
        end
        i_styleLightAx(ax);
    end
    exportgraphics(figM3, fullfile(outRoot, 'TKS-5_cm_All_1_to_8_OVL_S0_FSR_Curves_Montage_4x2.jpg'), 'Resolution', 150, 'BackgroundColor', 'white');
    close(figM3);

    fprintf('\n🎉 SELURUH PROSES SELESAI! Hasil lengkap tersimpan di:\n   %s\n', outRoot);
end

function [M, posPx, xPts, yPts] = i_sampleStackAlongImageLine(x1, y1, stackCell, p1, p2, spacing)
    nF = numel(stackCell);
    L = hypot(p2(1) - p1(1), p2(2) - p1(2));
    nPts = max(2, floor(L / spacing) + 1);
    xPts = linspace(p1(1), p2(1), nPts);
    yPts = linspace(p1(2), p2(2), nPts);
    posPx = hypot(xPts - p1(1), yPts - p1(2));

    xv = x1(1, :);
    yv = y1(:, 1);
    yMid = (max(yv) + min(yv)) / 2;
    ys_flipped = 2 * yMid - yPts;

    ci = i_nearestIdx(xv, xPts);
    ri = i_nearestIdx(yv, ys_flipped);

    M = nan(nPts, nF);
    for f = 1:nF
        F = stackCell{f};
        if isempty(F), continue; end
        for i = 1:nPts
            M(i, f) = i_mean3x3(F, ci(i), ri(i));
        end
    end
end

function idx = i_nearestIdx(vec, q)
    vec = vec(:);
    idx = zeros(1, numel(q));
    for i = 1:numel(q)
        [~, idx(i)] = min(abs(vec - q(i)));
    end
end

function m = i_mean3x3(F, ci, ri)
    [nR, nC] = size(F);
    r1 = max(1, ri - 1); r2 = min(nR, ri + 1);
    c1 = max(1, ci - 1); c2 = min(nC, ci + 1);
    sub = F(r1:r2, c1:c2);
    sub = sub(isfinite(sub));
    if isempty(sub), m = NaN; else, m = mean(sub); end
end

function s = i_formatRanges(idx)
    if isempty(idx), s = 'tidak ada'; return; end
    idx = sort(unique(idx(:)))';
    parts = {};
    i = 1;
    while i <= numel(idx)
        j = i;
        while j < numel(idx) && idx(j+1) == idx(j) + 1
            j = j + 1;
        end
        if i == j
            parts{end+1} = sprintf('%d', idx(i)); %#ok<AGROW>
        else
            parts{end+1} = sprintf('%d-%d', idx(i), idx(j)); %#ok<AGROW>
        end
        i = j + 1;
    end
    s = strjoin(parts, ', ');
end

function i_cleanDir(d)
    if isfolder(d)
        try, rmdir(d, 's'); catch, end
    end
end

function i_forceLightFig(fig)
    try, theme(fig, 'light'); catch, end
    try, fig.Theme = 'light'; catch, end
    try, fig.Color = [1 1 1]; catch, end
end

function i_styleLightAx(ax)
    try
        ax.Color = [1 1 1];
        ax.XColor = [0.1 0.1 0.1];
        ax.YColor = [0.1 0.1 0.1];
        ax.GridColor = [0.75 0.75 0.75];
        ax.GridAlpha = 0.45;
        ax.Title.Color = [0.05 0.05 0.05];
        ax.XLabel.Color = [0.1 0.1 0.1];
        ax.YLabel.Color = [0.1 0.1 0.1];
        box(ax, 'on');
    catch
    end
end
