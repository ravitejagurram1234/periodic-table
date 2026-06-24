package com.socgen.sgs.api.quark.engine.infra.api.v1;

import com.socgen.sgs.api.quark.engine.domain.RunProperties;
import com.socgen.sgs.api.quark.engine.dto.RunIdDto;
import com.socgen.sgs.api.quark.engine.service.ProcessRunService;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.WebMvcTest;
import org.springframework.boot.test.mock.mockito.MockBean;
import org.springframework.http.MediaType;
import org.springframework.security.test.context.support.WithMockUser;
import org.springframework.test.web.servlet.MockMvc;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.*;
import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.csrf;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.*;

@WebMvcTest(EngineServiceController.class)
@WithMockUser
@DisplayName("EngineServiceController Tests")
class EngineServiceControllerTest {

    @Autowired
    private MockMvc mockMvc;

    @MockBean
    private ProcessRunService processRunService;

    // --- POST /processRun/{runId} ---

    @Test
    @DisplayName("Should return 200 OK when run is processed successfully")
    void shouldReturn200WhenProcessRunSucceeds() throws Exception {
        // runProcessor returns a Run (not void), so stub a return value rather than doNothing().
        when(processRunService.runProcessor(any(RunIdDto.class))).thenReturn(null);

        mockMvc.perform(post("/ap/v1/EngineService/processRun/100")
                        .with(csrf())
                        .contentType(MediaType.APPLICATION_JSON))
                .andExpect(status().isOk())
                .andExpect(content().string("Run processed successfully"));

        verify(processRunService, times(1)).runProcessor(any(RunIdDto.class));
    }

    @Test
    @DisplayName("Should return 500 when runProcessor throws an exception")
    void shouldReturn500WhenProcessRunFails() throws Exception {
        doThrow(new RuntimeException("processing error"))
                .when(processRunService).runProcessor(any(RunIdDto.class));

        mockMvc.perform(post("/ap/v1/EngineService/processRun/100")
                        .with(csrf())
                        .contentType(MediaType.APPLICATION_JSON))
                .andExpect(status().isInternalServerError())
                .andExpect(content().string("Error processing run: processing error"));
    }

    @Test
    @DisplayName("Should pass correct runId to runProcessor")
    void shouldPassCorrectRunIdToProcessor() throws Exception {
        when(processRunService.runProcessor(any(RunIdDto.class))).thenReturn(null);

        mockMvc.perform(post("/ap/v1/EngineService/processRun/77")
                        .with(csrf()))
                .andExpect(status().isOk());

        verify(processRunService).runProcessor(argThat(dto -> dto.getRunId().equals(77)));
    }

    // --- GET /fetchRunProperties/{runId} ---

    @Test
    @DisplayName("Should return 200 with RunProperties body when found")
    void shouldReturn200WithRunProperties() throws Exception {
        RunProperties props = new RunProperties();
        props.setRunId(200);
        when(processRunService.getRunProperties(any(RunIdDto.class))).thenReturn(props);

        mockMvc.perform(get("/ap/v1/EngineService/fetchRunProperties/200")
                        .accept(MediaType.APPLICATION_JSON))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.runId").value(200));

        verify(processRunService, times(1)).getRunProperties(any(RunIdDto.class));
    }

    @Test
    @DisplayName("Should return 500 with null body when getRunProperties throws exception")
    void shouldReturn500WhenFetchRunPropertiesFails() throws Exception {
        when(processRunService.getRunProperties(any(RunIdDto.class)))
                .thenThrow(new RuntimeException("properties error"));

        mockMvc.perform(get("/ap/v1/EngineService/fetchRunProperties/99")
                        .accept(MediaType.APPLICATION_JSON))
                .andExpect(status().isInternalServerError());
    }

    @Test
    @DisplayName("Should pass correct runId to getRunProperties")
    void shouldPassCorrectRunIdToGetRunProperties() throws Exception {
        RunProperties props = new RunProperties();
        when(processRunService.getRunProperties(any(RunIdDto.class))).thenReturn(props);

        mockMvc.perform(get("/ap/v1/EngineService/fetchRunProperties/33"))
                .andExpect(status().isOk());

        verify(processRunService).getRunProperties(argThat(dto -> dto.getRunId().equals(33)));
    }
}
