document.addEventListener('DOMContentLoaded', () => {

    // ─── State ───────────────────────────────────────────
    let groups = [];
    let recentTestResults = {};

    // ─── DOM refs ────────────────────────────────────────
    const groupsContainer = document.getElementById('groups-container');
    const toastEl = document.getElementById('toast');

    // Modals
    const modalAdd = document.getElementById('modal-add-link');
    const addUrl = document.getElementById('add-url');
    const addGroup = document.getElementById('add-group');
    const addMsg = document.getElementById('add-message');
    const addPreview = document.getElementById('add-preview');
    const modalAddConfirm = document.getElementById('modal-add-confirm');
    const modalAddCancel = document.getElementById('modal-add-cancel');

    const modalImport = document.getElementById('modal-import');
    const importText = document.getElementById('import-text');
    const importGroup = document.getElementById('import-group');
    const importFile = document.getElementById('import-file');
    const importDropzone = document.getElementById('import-dropzone');
    const importMsg = document.getElementById('import-message');
    const modalImportConfirm = document.getElementById('modal-import-confirm');
    const modalImportCancel = document.getElementById('modal-import-cancel');

    const modalDeploy = document.getElementById('modal-deploy');
    const deployContainer = document.getElementById('deploy-container');
    const deployConfigPath = document.getElementById('deploy-config-path');
    const deployContainerPath = document.getElementById('deploy-container-path');
    const deployMsg = document.getElementById('deploy-message');
    const deployOutput = document.getElementById('deploy-output');
    const modalDeployConfirm = document.getElementById('modal-deploy-confirm');
    const modalDeployCancel = document.getElementById('modal-deploy-cancel');

    const modalEditGroup = document.getElementById('modal-edit-group');
    const editGroupName = document.getElementById('edit-group-name');
    let editingGroupId = null;
    const modalEditGroupConfirm = document.getElementById('modal-edit-group-confirm');
    const modalEditGroupCancel = document.getElementById('modal-edit-group-cancel');
    const modalEditGroupDelete = document.getElementById('modal-edit-group-delete');

    // Toolbar buttons
    const btnAddLink = document.getElementById('btn-add-link');
    const btnImport = document.getElementById('btn-import');
    const btnExport = document.getElementById('btn-export');
    const btnAddGroup = document.getElementById('btn-add-group');
    const btnTestAll = document.getElementById('btn-test-all');

    // ─── Toast ───────────────────────────────────────────
    function toast(text, type = 'info', duration = 3000) {
        toastEl.textContent = text;
        toastEl.className = `toast ${type}`;
        toastEl.classList.add('show');
        clearTimeout(toastEl._hide);
        toastEl._hide = setTimeout(() => toastEl.classList.remove('show'), duration);
    }

    // ─── API helpers ─────────────────────────────────────
    async function api(method, path, body = null) {
        const opts = { method, headers: {} };
        if (body && !(body instanceof FormData)) {
            opts.headers['Content-Type'] = 'application/json';
            opts.body = JSON.stringify(body);
        }
        const res = await fetch(path, opts);
        const data = await res.json();
        if (!res.ok) throw new Error(data.error || 'Request failed');
        return data;
    }

    async function apiText(method, path, body = null) {
        const opts = { method, headers: {} };
        if (body) opts.body = body;
        const res = await fetch(path, opts);
        if (!res.ok) throw new Error('Request failed');
        return await res.text();
    }

    // ─── Load & Render ──────────────────────────────────
    async function loadGroups() {
        try {
            groups = await api('GET', '/api/groups');
            renderGroups();
        } catch (err) {
            groupsContainer.innerHTML = `<div class="empty-group">❌ ${err.message}</div>`;
        }
    }

    function renderGroups() {
        if (!groups.length) {
            groupsContainer.innerHTML = `<div class="empty-group">暂无分组，点击「📁 分组」创建</div>`;
            return;
        }

        const html = groups.map((g) => {
            const proxyItems = g.proxies.map((p) => {
                const iconClass = `icon-${p.protocol}`;
                const disabledClass = !p.enabled ? 'disabled' : '';
                const testBadge = recentTestResults[p.id]
                    ? (recentTestResults[p.id].reachable
                        ? (recentTestResults[p.id].latency_ms != null
                            ? `<span class="latency-badge">⚡ ${recentTestResults[p.id].latency_ms}ms</span>`
                            : `<span class="latency-badge" style="background:rgba(102,126,234,0.2);color:#a0aec0;">✅ 可达</span>`)
                        : `<span class="latency-error">⚠️ ${recentTestResults[p.id].shortMsg || 'error'}</span>`)
                    : '';
                return `
                    <div class="proxy-item ${disabledClass}" data-id="${p.id}" data-group-id="${g.id}">
                        <span class="proxy-drag-handle">⠿</span>
                        <div class="proxy-icon ${iconClass}">${p.protocol.slice(0, 4)}</div>
                        <div class="proxy-info">
                            <div class="proxy-ps">${esc(p.ps || '未命名')}</div>
                            <div class="proxy-meta">
                                <span>🌐 ${esc(p.server)}:${p.port}</span>
                                ${p.protocol === 'vless' && p.flow ? `<span>🔄 ${esc(p.flow)}</span>` : ''}
                                ${p.security ? `<span>🔒 ${esc(p.security)}</span>` : ''}
                                ${p.network ? `<span>📡 ${esc(p.network)}</span>` : ''}
                                ${p.sni ? `<span>🎯 ${esc(p.sni)}</span>` : ''}
                                ${p.pbk ? `<span>🔑 pbk</span>` : ''}
                                ${testBadge}
                            </div>
                        </div>
                        <div class="proxy-toggle">
                            <button class="toggle ${p.enabled ? 'active' : ''}" data-id="${p.id}"></button>
                        </div>
                        <div class="proxy-default">
                            <button class="btn-star ${p.is_default ? 'active' : ''}" data-id="${p.id}">${p.is_default ? '⭐' : '☆'}</button>
                        </div>
                        <div class="proxy-actions">
                            <button class="btn btn-secondary btn-xs btn-test" data-id="${p.id}" title="测试连接">🧪</button>
                            <button class="btn btn-danger btn-xs btn-delete-proxy" data-id="${p.id}" title="删除">✕</button>
                        </div>
                    </div>
                `;
            }).join('');

            return `
                <div class="group-card" data-group-id="${g.id}">
                    <div class="group-header">
                        <span class="group-drag-handle">☰</span>
                        <input class="group-name" value="${esc(g.name)}" data-id="${g.id}" readonly>
                        <span class="group-badge">${g.proxies.length} 个</span>
                        <div class="group-actions">
                            <button class="btn btn-secondary btn-sm btn-edit-group" data-id="${g.id}" title="编辑分组">✏️</button>
                            <button class="btn btn-success btn-sm btn-export-group" data-id="${g.id}" title="导出该分组配置">📥</button>
                        </div>
                    </div>
                    <div class="proxy-list">
                        ${proxyItems || '<div class="empty-proxies">暂无代理，点击「➕ 添加」添加</div>'}
                    </div>
                </div>
            `;
        }).join('');

        groupsContainer.innerHTML = html;
        attachGroupEvents();
        attachProxyEvents();
    }

    function esc(text) {
        const div = document.createElement('div');
        div.textContent = text;
        return div.innerHTML;
    }

    // ─── Event: Groups ───────────────────────────────────
    function attachGroupEvents() {
        document.querySelectorAll('.group-name').forEach(input => {
            input.addEventListener('dblclick', () => {
                input.readOnly = false;
                input.focus();
            });
            input.addEventListener('blur', async () => {
                input.readOnly = true;
                const gid = input.dataset.id;
                const name = input.value.trim();
                if (name) {
                    await api('PUT', `/api/groups/${gid}`, { name });
                    toast('分组已重命名', 'success');
                }
            });
            input.addEventListener('keydown', (e) => {
                if (e.key === 'Enter') input.blur();
            });
        });

        document.querySelectorAll('.btn-edit-group').forEach(btn => {
            btn.addEventListener('click', () => {
                const gid = parseInt(btn.dataset.id);
                const group = groups.find(g => g.id === gid);
                if (!group) return;
                editingGroupId = gid;
                editGroupName.value = group.name;
                modalEditGroup.classList.remove('hidden');
            });
        });

        document.querySelectorAll('.btn-export-group').forEach(btn => {
            btn.addEventListener('click', () => {
                const gid = btn.dataset.id;
                window.open(`/api/export/xray?group_id=${gid}`, '_blank');
                toast('正在下载分组配置', 'info');
            });
        });
    }

    // ─── Event: Proxies ──────────────────────────────────
    function attachProxyEvents() {
        // Toggle
        document.querySelectorAll('.toggle').forEach(tog => {
            tog.addEventListener('click', async () => {
                const pid = parseInt(tog.dataset.id);
                const active = tog.classList.contains('active');
                try {
                    await api('PUT', `/api/links/${pid}`, { enabled: !active });
                    toast(!active ? '代理已启用' : '代理已禁用', 'info');
                    await loadGroups();
                } catch (err) {
                    toast(err.message, 'error');
                }
            });
        });

        // Default star
        document.querySelectorAll('.btn-star').forEach(star => {
            star.addEventListener('click', async () => {
                const pid = parseInt(star.dataset.id);
                const gid = parseInt(star.closest('.group-card').dataset.groupId);
                const proxy = groups.find(g => g.id === gid)?.proxies.find(p => p.id === pid);
                if (!proxy) return;
                const newDefault = proxy.is_default ? null : pid;
                try {
                    await api('PUT', `/api/groups/${gid}`, { default_proxy_id: newDefault });
                    toast(newDefault ? '已设为默认出口' : '已取消默认', 'success');
                    await loadGroups();
                } catch (err) {
                    toast(err.message, 'error');
                }
            });
        });

        // Delete
        document.querySelectorAll('.btn-delete-proxy').forEach(btn => {
            btn.addEventListener('click', async () => {
                if (!confirm('确定删除此代理？')) return;
                const pid = btn.dataset.id;
                try {
                    await api('DELETE', `/api/links/${pid}`);
                    toast('已删除', 'success');
                    delete recentTestResults[pid];
                    await loadGroups();
                } catch (err) {
                    toast(err.message, 'error');
                }
            });
        });

        // Test
        document.querySelectorAll('.btn-test').forEach(btn => {
            btn.addEventListener('click', async () => {
                const pid = btn.dataset.id;
                btn.classList.add('testing');
                btn.disabled = true;
                try {
                    const res = await fetch(`/api/links/${pid}/test`, { method: 'POST' });
                    const data = await res.json();
                    // Determine best result based on what's available
                    let best = null;
                    let label = '';

                    if (data.tcp) {
                        best = data.tcp;
                        label = 'TCP';
                    } else if (data.udp) {
                        best = data.udp;
                        label = 'UDP';
                    } else if (data.icmp) {
                        best = data.icmp;
                        label = 'ICMP';
                    }

                    if (best) {
                        recentTestResults[pid] = {
                            reachable: best.reachable,
                            latency_ms: best.latency_ms,
                            shortMsg: best.reachable ? '' : (best.message || 'unreachable')
                        };
                        if (best.reachable && best.latency_ms) {
                            toast(`✅ ${label} ${best.latency_ms}ms`, 'success', 3000);
                        } else if (best.reachable) {
                            toast(`✅ ${label} 可达`, 'success', 3000);
                        } else {
                            toast(`❌ ${label}: ${best.message}`, 'error', 5000);
                        }
                    } else {
                        recentTestResults[pid] = {
                            reachable: false,
                            latency_ms: null,
                            shortMsg: 'No test data'
                        };
                        toast('❌ 无法获取测试结果', 'error', 3000);
                    }
                    await loadGroups();
                } catch (err) {
                    toast(err.message, 'error');
                } finally {
                    btn.classList.remove('testing');
                    btn.disabled = false;
                }
            });
        });
    }

    // ─── Add Link ────────────────────────────────────────
    btnAddLink.addEventListener('click', () => {
        addUrl.value = '';
        addPreview.textContent = '';
        addMsg.className = 'message';
        addMsg.style.display = 'none';
        addGroup.innerHTML = '<option value="">无分组</option>' +
            groups.map(g => `<option value="${g.id}">${esc(g.name)}</option>`).join('');
        modalAdd.classList.remove('hidden');
        addUrl.focus();
    });

    addUrl.addEventListener('input', () => {
        const url = addUrl.value.trim();
        if (url.startsWith('vless://') || url.startsWith('vmess://') || url.startsWith('ss://') ||
            url.startsWith('trojan://') || url.startsWith('hysteria2://') || url.startsWith('hy2://') ||
            url.startsWith('tuic://')) {
            addPreview.textContent = '🔍 链接识别中...';
        } else {
            addPreview.textContent = '';
        }
    });

    modalAddCancel.addEventListener('click', () => modalAdd.classList.add('hidden'));
    modalAddConfirm.addEventListener('click', async () => {
        const url = addUrl.value.trim();
        if (!url) { addMsg.textContent = '请输入链接'; addMsg.className = 'message error show'; return; }
        const groupId = addGroup.value ? parseInt(addGroup.value) : null;
        try {
            await api('POST', '/api/links', { url, group_id: groupId });
            toast('✅ 已添加', 'success');
            modalAdd.classList.add('hidden');
            await loadGroups();
        } catch (err) {
            addMsg.textContent = err.message;
            addMsg.className = 'message error show';
        }
    });
    addUrl.addEventListener('keydown', (e) => { if (e.key === 'Enter') modalAddConfirm.click(); });

    // ─── Import ──────────────────────────────────────────
    btnImport.addEventListener('click', () => {
        importText.value = '';
        importMsg.className = 'message';
        importMsg.style.display = 'none';
        importGroup.innerHTML = '<option value="">自动分配到默认分组</option>' +
            groups.map(g => `<option value="${g.id}">${esc(g.name)}</option>`).join('');
        modalImport.classList.remove('hidden');
    });

    modalImportCancel.addEventListener('click', () => modalImport.classList.add('hidden'));

    // File drop
    importDropzone.addEventListener('click', () => importFile.click());
    importDropzone.addEventListener('dragover', (e) => { e.preventDefault(); importDropzone.classList.add('dragover'); });
    importDropzone.addEventListener('dragleave', () => importDropzone.classList.remove('dragover'));
    importDropzone.addEventListener('drop', (e) => {
        e.preventDefault();
        importDropzone.classList.remove('dragover');
        if (e.dataTransfer.files.length) handleImportFile(e.dataTransfer.files[0]);
    });
    importFile.addEventListener('change', () => {
        if (importFile.files.length) handleImportFile(importFile.files[0]);
    });

    function handleImportFile(file) {
        const reader = new FileReader();
        reader.onload = (e) => {
            importText.value = e.target.result;
        };
        reader.readAsText(file);
    }

    modalImportConfirm.addEventListener('click', async () => {
        const text = importText.value.trim();
        if (!text) { importMsg.textContent = '请输入或选择要导入的内容'; importMsg.className = 'message error show'; return; }
        const groupId = importGroup.value ? parseInt(importGroup.value) : null;
        const params = groupId ? `?group_id=${groupId}` : '';
        importMsg.textContent = '导入中...';
        importMsg.className = 'message info show';
        modalImportConfirm.disabled = true;
        try {
            const data = await api('POST', `/api/links/import${params}`, text);
            importMsg.textContent = `✅ 导入完成：新增 ${data.imported} 个，跳过 ${data.skipped} 个`;
            importMsg.className = 'message success show';
            toast(`导入 ${data.imported} 个链接`, 'success');
            await loadGroups();
            // Auto close after 2s
            setTimeout(() => { modalImport.classList.add('hidden'); }, 2000);
        } catch (err) {
            importMsg.textContent = err.message;
            importMsg.className = 'message error show';
        } finally {
            modalImportConfirm.disabled = false;
        }
    });

    // ─── Export ──────────────────────────────────────────
    btnExport.addEventListener('click', () => {
        window.open('/api/links/export', '_blank');
        toast('正在下载链接列表', 'info');
    });

    // ─── Edit Group ───────────────────────────────────────
    modalEditGroupCancel.addEventListener('click', () => { modalEditGroup.classList.add('hidden'); });
    modalEditGroupConfirm.addEventListener('click', async () => {
        const name = editGroupName.value.trim();
        if (!name) return;
        try {
            await api('PUT', `/api/groups/${editingGroupId}`, { name });
            toast('分组已保存', 'success');
            modalEditGroup.classList.add('hidden');
            await loadGroups();
        } catch (err) {
            toast(err.message, 'error');
        }
    });
    modalEditGroupDelete.addEventListener('click', async () => {
        if (!confirm('确定删除此分组？其下的代理会变为"无分组"状态。')) return;
        try {
            await api('DELETE', `/api/groups/${editingGroupId}`);
            toast('分组已删除', 'info');
            modalEditGroup.classList.add('hidden');
            await loadGroups();
        } catch (err) {
            toast(err.message, 'error');
        }
    });
    editGroupName.addEventListener('keydown', (e) => { if (e.key === 'Enter') modalEditGroupConfirm.click(); });

    // ─── Add Group ────────────────────────────────────────
    btnAddGroup.addEventListener('click', async () => {
        const name = prompt('请输入新分组名称：', '新分组');
        if (!name || !name.trim()) return;
        try {
            await api('POST', '/api/groups', { name: name.trim() });
            toast('✅ 分组已创建', 'success');
            await loadGroups();
        } catch (err) {
            toast(err.message, 'error');
        }
    });

    // ─── Global Speed Test ──────────────────────────────────
    btnTestAll.addEventListener('click', async () => {
        // Collect all proxy IDs
        const allProxyIds = [];
        for (const g of groups) {
            for (const p of g.proxies) {
                allProxyIds.push(p.id);
            }
        }
        if (!allProxyIds.length) {
            toast('没有代理可测试', 'info');
            return;
        }

        btnTestAll.disabled = true;
        btnTestAll.textContent = '⏳ 测速中...';
        const total = allProxyIds.length;
        let completed = 0;
        let reachable = 0;

        // Collect all .btn-test elements by mapping proxy IDs
        const testButtons = {};
        document.querySelectorAll('.btn-test').forEach(btn => {
            testButtons[btn.dataset.id] = btn;
        });

        for (const pid of allProxyIds) {
            const btn = testButtons[pid];
            if (btn) {
                btn.classList.add('testing');
                btn.disabled = true;
            }
            try {
                const res = await fetch(`/api/links/${pid}/test`, { method: 'POST' });
                const data = await res.json();
                completed++;

                // Determine best result
                let best = data.tcp || data.udp || data.icmp || null;
                if (best && best.reachable) {
                    reachable++;
                    recentTestResults[pid] = {
                        reachable: true,
                        latency_ms: best.latency_ms,
                        shortMsg: ''
                    };
                } else if (best) {
                    recentTestResults[pid] = {
                        reachable: false,
                        latency_ms: null,
                        shortMsg: best.message || 'unreachable'
                    };
                } else {
                    recentTestResults[pid] = {
                        reachable: false,
                        latency_ms: null,
                        shortMsg: 'No test data'
                    };
                }
            } catch (err) {
                completed++;
                recentTestResults[pid] = { reachable: false, latency_ms: null, shortMsg: err.message };
            } finally {
                if (btn) {
                    btn.classList.remove('testing');
                    btn.disabled = false;
                }
                // Update toolbar progress
                btnTestAll.textContent = `⏳ ${completed}/${total}`;
            }
        }

        btnTestAll.disabled = false;
        btnTestAll.textContent = '🌐 全局测速';
        await loadGroups();
        toast(`测速完成：${reachable}/${total} 个可连接`, reachable > 0 ? 'success' : 'error');
    });

    // ─── Close modals on overlay click ──────────────────
    document.querySelectorAll('.modal-overlay').forEach(el => {
        el.addEventListener('click', (e) => {
            if (e.target === el) el.classList.add('hidden');
        });
    });

    // ─── Engine DOM refs ────────────────────────────────
    const engineBadge = document.getElementById('engine-status-badge');
    const enginePid = document.getElementById('engine-pid');
    const btnEngineDownload = document.getElementById('btn-engine-download');
    const btnEngineStart = document.getElementById('btn-engine-start');
    const btnEngineStop = document.getElementById('btn-engine-stop');

    // ─── Engine Control ─────────────────────────────────

    async function checkEngineStatus() {
        try {
            const resp = await fetch('/api/core/status');
            const data = await resp.json();
            if (data.running) {
                engineBadge.className = 'badge badge-online';
                engineBadge.textContent = '▶ 运行中';
                enginePid.textContent = `PID: ${data.pid || '?'}`;
                btnEngineStart.disabled = true;
                btnEngineStop.disabled = false;
            } else {
                engineBadge.className = 'badge badge-offline';
                engineBadge.textContent = '⏻ 停止';
                enginePid.textContent = '';
                btnEngineStart.disabled = !data.binary_exists;
                btnEngineStop.disabled = true;
            }
            btnEngineDownload.disabled = false;
        } catch(e) {
            engineBadge.className = 'badge badge-offline';
            engineBadge.textContent = '⚠ 离线';
            enginePid.textContent = '';
        }
    }

    btnEngineDownload.addEventListener('click', async () => {
        btnEngineDownload.disabled = true;
        btnEngineDownload.textContent = '⏳ 下载中...';
        engineBadge.className = 'badge badge-downloading';
        engineBadge.textContent = '⏳ 下载中';
        try {
            const resp = await fetch('/api/core/download', { method: 'POST' });
            const data = await resp.json();
            if (resp.ok) {
                toast(data.message, 'success');
                await checkEngineStatus();
            } else {
                toast(data.error || '下载失败', 'error');
            }
        } catch(e) {
            toast('下载失败: ' + e.message, 'error');
        } finally {
            btnEngineDownload.disabled = false;
            btnEngineDownload.textContent = '⬇ 下载引擎';
        }
    });

    btnEngineStart.addEventListener('click', async () => {
        btnEngineStart.disabled = true;
        btnEngineStart.textContent = '⏳ 启动中...';
        try {
            const resp = await fetch('/api/core/start', { method: 'POST' });
            const data = await resp.json();
            if (resp.ok) {
                toast(data.message, 'success');
                await checkEngineStatus();
            } else {
                toast(data.error || '启动失败', 'error');
                btnEngineStart.disabled = false;
                btnEngineStart.textContent = '▶ 启动';
            }
        } catch(e) {
            toast('启动失败: ' + e.message, 'error');
            btnEngineStart.disabled = false;
            btnEngineStart.textContent = '▶ 启动';
        }
    });

    btnEngineStop.addEventListener('click', async () => {
        btnEngineStop.disabled = true;
        btnEngineStop.textContent = '⏳ 停止中...';
        try {
            const resp = await fetch('/api/core/stop', { method: 'POST' });
            const data = await resp.json();
            if (resp.ok) {
                toast('代理已停止', 'info');
                await checkEngineStatus();
            } else {
                toast(data.error || '停止失败', 'error');
            }
        } catch(e) {
            toast('停止失败: ' + e.message, 'error');
        } finally {
            btnEngineStop.disabled = false;
            btnEngineStop.textContent = '⏹ 停止';
        }
    });

    // ─── Init ────────────────────────────────────────────
    checkEngineStatus();
    loadGroups();

    // Auto-refresh every 60s
    setInterval(loadGroups, 60000);
});
